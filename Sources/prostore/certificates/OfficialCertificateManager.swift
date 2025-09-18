import Foundation
import ZIPFoundation

enum CertType: String {
    case signed = "Signed"
    case revoked = "Revoked"
}

struct Cert: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let downloadURL: URL
    let type: CertType
    let lastModified: Date?
}

@MainActor
class OfficialCertificateManager: ObservableObject {
    @Published var certs: [Cert] = []
    @Published var featuredCert: Cert?
    @Published var currentStatus = ""
    @Published var isProcessing = false
    
    func loadCerts() async {
        guard let tokenURL = URL(string: "https://certapi.loyah.dev/pac") else { return }
        do {
            let (tokenData, _) = try await URLSession.shared.data(from: tokenURL)
            guard let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return }
            
            let signedAPIURL = URL(string: "https://api.github.com/repos/loyahdev/certificates/contents/certs/signed")!
            var request = URLRequest(url: signedAPIURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (signedData, _) = try await URLSession.shared.data(for: request)
            let signedJSON = try JSONSerialization.jsonObject(with: signedData) as? [[String: Any]] ?? []
            let signedFiles = signedJSON.compactMap { dict -> (name: String, downloadURL: String, path: String)? in
                guard let name = dict["name"] as? String, name.hasSuffix(".zip"),
                      let dl = dict["download_url"] as? String else { return nil }
                return (name, dl, "certs/signed/\(name)")
            }
            
            let revokedAPIURL = URL(string: "https://api.github.com/repos/loyahdev/certificates/contents/certs/revoked")!
            request.url = revokedAPIURL
            let (revokedData, _) = try await URLSession.shared.data(for: request)
            let revokedJSON = try JSONSerialization.jsonObject(with: revokedData) as? [[String: Any]] ?? []
            let revokedFiles = revokedJSON.compactMap { dict -> (name: String, downloadURL: String, path: String)? in
                guard let name = dict["name"] as? String, name.hasSuffix(".zip"),
                      let dl = dict["download_url"] as? String else { return nil }
                return (name, dl, "certs/revoked/\(name)")
            }
            
            let allFiles = signedFiles + revokedFiles
            
            let dates = try await withThrowingTaskGroup(of: (String, String, String, Date?).self) { group in
                for file in allFiles {
                    let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file.path
                    let commitsURL = URL(string: "https://api.github.com/repos/loyahdev/certificates/commits?path=\(encodedPath)&per_page=1")!
                    var req = URLRequest(url: commitsURL)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                    
                    group.addTask {
                        do {
                            let (data, _) = try await URLSession.shared.data(for: req)
                            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                               let first = arr.first,
                               let commitDict = first["commit"] as? [String: Any],
                               let authorDict = commitDict["author"] as? [String: Any],
                               let dateStr = authorDict["date"] as? String {
                                let formatter = ISO8601DateFormatter()
                                let date = formatter.date(from: dateStr)
                                return (file.name, file.downloadURL, file.path, date)
                            }
                        } catch {
                            print("Date fetch error for \(file.name): \(error)")
                        }
                        return (file.name, file.downloadURL, file.path, nil)
                    }
                }
                
                var results: [(String, String, String, Date?)] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            var newCerts: [Cert] = []
            for (name, dlStr, path, date) in dates {
                guard let dlURL = URL(string: dlStr) else { continue }
                let type: CertType = path.contains("/signed/") ? .signed : .revoked
                let cleanName = String(name.dropLast(4)) // Remove .zip
                newCerts.append(Cert(name: cleanName, downloadURL: dlURL, type: type, lastModified: date))
            }
            
            // Sort signed and revoked separately by date desc (recent first)
            let signedCerts = newCerts.filter { $0.type == .signed }.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
            let revokedCerts = newCerts.filter { $0.type == .revoked }.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
            certs = signedCerts + revokedCerts
            
            featuredCert = signedCerts.first ?? revokedCerts.first
        } catch {
            print("Load official certs error: \(error)")
        }
    }
    
    func checkCert(_ cert: Cert) async {
        isProcessing = true
        currentStatus = "Checking..."
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            
            let (zipData, _) = try await URLSession.shared.data(from: cert.downloadURL)
            let tempZipURL = tempDir.appendingPathComponent("cert.zip")
            try zipData.write(to: tempZipURL)
            
            // Unzip using ZIPFoundation
            try FileManager.default.unzipItem(at: tempZipURL, to: tempDir)
            
            // Find the extraction directory (root or single subdir)
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            var searchDir = tempDir
            if contents.count == 1 {
                let firstItem = contents[0]
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: firstItem.path, isDirectory: &isDir), isDir.boolValue {
                    searchDir = firstItem
                }
            }
            
            let fileContents = try FileManager.default.contentsOfDirectory(at: searchDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            var p12URL: URL?
            var provURL: URL?
            var txtURL: URL?
            
            for url in fileContents {
                let ext = url.pathExtension.lowercased()
                if ext == "p12" { p12URL = url }
                else if ext == "mobileprovision" { provURL = url }
                else if ext == "txt" { txtURL = url }
            }
            
            guard let p12U = p12URL, let provU = provURL, let txtU = txtURL else {
                throw NSError(domain: "MissingFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zip missing p12, provision, or txt"])
            }
            
            let txtData = try Data(contentsOf: txtU)
            let password = String(data: txtData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            let p12Data = try Data(contentsOf: p12U)
            let provData = try Data(contentsOf: provU)
            
            let result = CertificatesManager.check(p12Data: p12Data, password: password, mobileProvisionData: provData)
            
            switch result {
            case .success(.success):
                currentStatus = "Success!"
            case .success(.incorrectPassword):
                currentStatus = "Incorrect Password"
            case .success(.noMatch):
                currentStatus = "P12 and MobileProvision do not match"
            case .failure(let err):
                print("Official check error: \(err)")
                currentStatus = "P12 and MobileProvision do not match"
            }
        } catch {
            print("Official cert process error: \(error)")
            currentStatus = "Error: Couldn't process zip"
        }
        
        isProcessing = false
    }
}