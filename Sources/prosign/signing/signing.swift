import Foundation
import ZsignSwift
import ZIPFoundation

struct FileItem {
    var url: URL?
    var name: String { url?.lastPathComponent ?? "" }
}

class SigningManager {
    static func sign(
        appPath: String,
        provisionPath: String,
        p12Path: String,
        p12Password: String,
        entitlementsPath: String,
        removeProvision: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        // Explicitly discard result to silence "result unused" warning
        _ = Zsign.sign(
            appPath: appPath,
            provisionPath: provisionPath,
            p12Path: p12Path,
            p12Password: p12Password,
            entitlementsPath: entitlementsPath,
            removeProvision: removeProvision,
            completion: completion
        )
    }
    
    static func prepareTemporaryWorkspace() throws -> (URL, URL, URL) {
        let fm = FileManager.default
        let tmpRoot = fm.temporaryDirectory.appendingPathComponent("zsign_ios_\(UUID().uuidString)")
        let inputs = tmpRoot.appendingPathComponent("inputs")
        let work = tmpRoot.appendingPathComponent("work")
        try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        return (tmpRoot, inputs, work)
    }
    
    static func copyInputFiles(ipaURL: URL, p12URL: URL, provURL: URL, to inputsDir: URL) throws -> (URL, URL, URL) {
        let fm = FileManager.default
        
        let localIPA = inputsDir.appendingPathComponent(ipaURL.lastPathComponent)
        let localP12 = inputsDir.appendingPathComponent(p12URL.lastPathComponent)
        let localProv = inputsDir.appendingPathComponent(provURL.lastPathComponent)
        
        [localIPA, localP12, localProv].forEach {
            if fm.fileExists(atPath: $0.path) {
                try? fm.removeItem(at: $0)
            }
        }
        
        try fm.copyItem(at: ipaURL, to: localIPA)
        try fm.copyItem(at: p12URL, to: localP12)
        try fm.copyItem(at: provURL, to: localProv)
        
        return (localIPA, localP12, localProv)
    }
    
    static func extractIPA(ipaURL: URL, to workDir: URL) throws {
        // Use throwing initializer (deprecated non-throwing variant removed)
        let archive = try Archive(url: ipaURL, accessMode: .read)
        
        let fm = FileManager.default
        for entry in archive {
            let dest = workDir.appendingPathComponent(entry.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.type == .directory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                // Explicit discard in case extract returns a value in this version
                _ = try archive.extract(entry, to: dest)
            }
        }
    }
    
    static func findAppBundle(in payloadDir: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: payloadDir.path) else {
            throw NSError(domain: "Zsign", code: 1, userInfo: [NSLocalizedDescriptionKey: "Payload not found"])
        }
        
        let contents = try fm.contentsOfDirectory(atPath: payloadDir.path)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw NSError(domain: "Zsign", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle in Payload"])
        }
        
        return payloadDir.appendingPathComponent(appName)
    }
    
    static func createSignedIPA(from workDir: URL, originalIPAURL: URL, outputDir: URL) throws -> URL {
        let fm = FileManager.default
        
        let originalBase = originalIPAURL.deletingPathExtension().lastPathComponent
        let finalFileName = "\(originalBase)_signed_\(UUID().uuidString).ipa"
        let signedIpa = outputDir.appendingPathComponent(finalFileName)
        
        // Throwing initializer
        let writeArchive = try Archive(url: signedIpa, accessMode: .create)
        
        let enumerator = fm.enumerator(at: workDir, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil)!
        var directories: [URL] = []
        var filesList: [URL] = []
        
        for case let file as URL in enumerator {
            if file == workDir { continue }
            let isDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? file.hasDirectoryPath
            if isDir { directories.append(file) } else { filesList.append(file) }
        }
        
        directories.sort { $0.path.count < $1.path.count }
        let base = workDir
        
        for dir in directories {
            let relative = dir.path.replacingOccurrences(of: base.path + "/", with: "")
            let entryPath = relative.hasSuffix("/") ? relative : relative + "/"
            try writeArchive.addEntry(with: entryPath, relativeTo: base, compressionMethod: .none)
        }
        
        for file in filesList {
            let relative = file.path.replacingOccurrences(of: base.path + "/", with: "")
            try writeArchive.addEntry(with: relative, relativeTo: base, compressionMethod: .deflate)
        }
        
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outURL = docs.appendingPathComponent(finalFileName)
        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
        try fm.copyItem(at: signedIpa, to: outURL)
        
        return outURL
    }
    
    static func cleanupTemporaryFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    static func processSigning(
        ipaURL: URL,
        p12URL: URL,
        provURL: URL,
        p12Password: String,
        progressUpdate: @escaping (String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                progressUpdate("Preparing files 📂")
                
                let (tmpRoot, inputsDir, workDir) = try prepareTemporaryWorkspace()
                defer { cleanupTemporaryFiles(at: tmpRoot) }
                
                let (localIPA, localP12, localProv) = try copyInputFiles(
                    ipaURL: ipaURL,
                    p12URL: p12URL,
                    provURL: provURL,
                    to: inputsDir
                )
                
                progressUpdate("Unzipping IPA 🔓")
                try extractIPA(ipaURL: localIPA, to: workDir)
                
                let payloadDir = workDir.appendingPathComponent("Payload")
                let appDir = try findAppBundle(in: payloadDir)
                
                progressUpdate("Signing \(appDir.lastPathComponent) ✍️")
                
                // Replace spin-wait with semaphore (optional improvement)
                let sema = DispatchSemaphore(value: 0)
                var signingError: Error?
                
                sign(
                    appPath: appDir.path,
                    provisionPath: localProv.path,
                    p12Path: localP12.path,
                    p12Password: p12Password,
                    entitlementsPath: "",
                    removeProvision: false
                ) { _, error in
                    signingError = error
                    sema.signal()
                }
                
                sema.wait()
                if let error = signingError { throw error }
                
                progressUpdate("Zipping signed IPA 📦")
                let signedIPAURL = try createSignedIPA(
                    from: workDir,
                    originalIPAURL: ipaURL,
                    outputDir: tmpRoot
                )
                
                completion(.success(signedIPAURL))
                
            } catch {
                completion(.failure(error))
            }
        }
    }
}