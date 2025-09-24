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
    var status: String = ""
    var isProcessing: Bool = false
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
        // Find the cert in our list so we can update its individual state
        guard let index = certs.firstIndex(where: { $0.id == cert.id }) else { return }

        // Mark this cert as processing (individual + global)
        certs[index].isProcessing = true
        certs[index].status = "Checking..."
        isProcessing = true
        currentStatus = certs[index].status

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            certs[index].status = "Downloading zip..."
            currentStatus = certs[index].status
            let (zipData, _) = try await URLSession.shared.data(from: cert.downloadURL)
            let tempZipURL = tempDir.appendingPathComponent("cert.zip")
            try zipData.write(to: tempZipURL)

            certs[index].status = "Unzipping..."
            currentStatus = certs[index].status
            // Unzip using ZIPFoundation
            try FileManager.default.unzipItem(at: tempZipURL, to: tempDir)

            // Recursively enumerate files and ignore any path that contains __MACOSX
            var p12Urls: [URL] = []
            var provUrls: [URL] = []
            var txtUrls: [URL] = []

            let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles], errorHandler: nil)
            while let item = enumerator?.nextObject() as? URL {
                // skip anything in a __MACOSX folder
                if item.pathComponents.contains("__MACOSX") { continue }
                // only consider files
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue { continue }

                let ext = item.pathExtension.lowercased()
                if ext == "p12" {
                    p12Urls.append(item)
                } else if ext == "mobileprovision" {
                    provUrls.append(item)
                } else if ext == "txt" {
                    txtUrls.append(item)
                }
            }

            // Helper: extract the highest integer from a filename (returns nil if none)
            func highestNumber(in string: String) -> Int? {
                do {
                    let regex = try NSRegularExpression(pattern: "\\d+", options: [])
                    let ns = string as NSString
                    let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: ns.length))
                    let ints = matches.compactMap { match -> Int? in
                        let numStr = ns.substring(with: match.range)
                        return Int(numStr)
                    }
                    return ints.max()
                } catch {
                    return nil
                }
            }

            // Choose mobile provision: if multiple, pick one with highest number in filename, otherwise random
            var chosenProvURL: URL?
            if provUrls.count == 1 {
                chosenProvURL = provUrls.first
            } else if provUrls.count > 1 {
                // Map each URL to its highest number (if any)
                var best: (url: URL, num: Int?)?
                for u in provUrls {
                    let name = u.lastPathComponent
                    let num = highestNumber(in: name)
                    if best == nil {
                        best = (u, num)
                    } else {
                        switch (best!.num, num) {
                        case (nil, nil):
                            // keep current best (we'll pick random fallback below if none have numbers)
                            break
                        case (nil, .some):
                            best = (u, num)
                        case (.some(let a), .some(let b)):
                            if b > a { best = (u, num) }
                        case (.some, nil):
                            break
                        }
                    }
                }
                if let bestNum = best?.num {
                    // There was at least one with a number — pick the one with max number
                    let maxNumber = bestNum
                    if let pick = provUrls.first(where: { highestNumber(in: $0.lastPathComponent) == maxNumber }) {
                        chosenProvURL = pick
                    }
                } else {
                    // no numbers found in any filename — pick random
                    chosenProvURL = provUrls.randomElement()
                }
            }

            // Basic selection for p12 and txt: pick the first found (could be improved if you want)
            let chosenP12URL = p12Urls.first
            let chosenTxtURL = txtUrls.first

            // Validate that we have required files
            guard let p12U = chosenP12URL, let provU = chosenProvURL, let txtU = chosenTxtURL else {
                certs[index].status = "Error: Missing p12, mobileprovision or txt"
                currentStatus = certs[index].status
                throw NSError(domain: "MissingFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zip missing p12, provision, or txt"])
            }

            certs[index].status = "Reading files..."
            currentStatus = certs[index].status

            let txtData = try Data(contentsOf: txtU)
            let password = String(data: txtData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let p12Data = try Data(contentsOf: p12U)
            let provData = try Data(contentsOf: provU)

            certs[index].status = "Verifying certificate..."
            currentStatus = certs[index].status
            let result = CertificatesManager.check(p12Data: p12Data, password: password, mobileProvisionData: provData)

            switch result {
            case .success(.success):
                certs[index].status = "Success!"
            case .success(.incorrectPassword):
                certs[index].status = "Incorrect Password"
            case .success(.noMatch):
                certs[index].status = "P12 and MobileProvision do not match"
            case .failure(let err):
                print("Official check error: \(err)")
                certs[index].status = "P12 and MobileProvision do not match"
            }
        } catch {
            print("Official cert process error: \(error)")
            certs[index].status = "Error: Couldn't process zip"
        }

        // Turn off this cert's processing flag and refresh global processing state + currentStatus
        certs[index].isProcessing = false
        isProcessing = certs.contains(where: { $0.isProcessing })
        currentStatus = certs[index].status
    }
}