// CertificateView.swift
import SwiftUI
import UniformTypeIdentifiers

// Centralized types to avoid conflicts
struct CertificateFileItem {
    var name: String = ""
    var url: URL?
}

struct CustomCertificate: Identifiable {
    let id = UUID()
    let displayName: String
    let folderName: String
}

class CertificateFileManager {
    static let shared = CertificateFileManager()
    private let fileManager = FileManager.default
    private let certificatesDirectory: URL
    
    private init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        certificatesDirectory = documentsDirectory.appendingPathComponent("certificates")
        createCertificatesDirectoryIfNeeded()
    }
    
    private func createCertificatesDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: certificatesDirectory.path) {
            try? fileManager.createDirectory(at: certificatesDirectory, withIntermediateDirectories: true)
        }
    }
    
    func loadCertificates() -> [CustomCertificate] {
        guard let subdirectories = try? fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var certificates: [CustomCertificate] = []
        for folder in subdirectories {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), !isDir.boolValue { continue }
            
            let nameURL = folder.appendingPathComponent("name.txt")
            if fileManager.fileExists(atPath: nameURL.path) {
                do {
                    let nameData = try Data(contentsOf: nameURL)
                    if let displayName = String(data: nameData, encoding: .utf8) {
                        certificates.append(CustomCertificate(displayName: displayName, folderName: folder.lastPathComponent))
                    }
                } catch {
                    print("Error loading name: \(error)")
                }
            }
        }
        return certificates.sorted { $0.displayName < $1.displayName }
    }
    
    func saveCertificate(p12Data: Data, provData: Data, password: String, displayName: String) throws -> String {
        let baseName = sanitizeFileName(displayName.isEmpty ? "Custom Certificate" : displayName)
        let p12HashNew = CertificatesManager.sha256Hex(p12Data)
        let provHashNew = CertificatesManager.sha256Hex(provData)
        let passwordHashNew = CertificatesManager.sha256Hex(password.data(using: .utf8) ?? Data())
        
        // Check if identical cert already exists
        let existingFolders = try fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for folder in existingFolders {
            let p12URL = folder.appendingPathComponent("certificate.p12")
            let provURL = folder.appendingPathComponent("profile.mobileprovision")
            let passwordURL = folder.appendingPathComponent("password.txt")
            
            if fileManager.fileExists(atPath: p12URL.path) && fileManager.fileExists(atPath: provURL.path) && fileManager.fileExists(atPath: passwordURL.path) {
                do {
                    let existingP12Data = try Data(contentsOf: p12URL)
                    let existingProvData = try Data(contentsOf: provURL)
                    let existingPasswordData = try Data(contentsOf: passwordURL)
                    let existingPassword = String(data: existingPasswordData, encoding: .utf8) ?? ""
                    
                    let p12HashExisting = CertificatesManager.sha256Hex(existingP12Data)
                    let provHashExisting = CertificatesManager.sha256Hex(existingProvData)
                    let passwordHashExisting = CertificatesManager.sha256Hex(existingPassword.data(using: .utf8) ?? Data())
                    
                    if p12HashNew == p12HashExisting && provHashNew == provHashExisting && passwordHashNew == passwordHashExisting {
                        throw NSError(domain: "CertificateFileManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "This certificate already exists"])
                    }
                } catch {
                    // Skip if can't read existing
                    continue
                }
            }
        }
        
        // Find unique folder name
        var candidate = baseName
        var count = 1
        while fileManager.fileExists(atPath: certificatesDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(baseName) (\(count))"
            count += 1
        }
        
        let certificateFolder = certificatesDirectory.appendingPathComponent(candidate)
        try fileManager.createDirectory(at: certificateFolder, withIntermediateDirectories: true)
        
        try p12Data.write(to: certificateFolder.appendingPathComponent("certificate.p12"))
        try provData.write(to: certificateFolder.appendingPathComponent("profile.mobileprovision"))
        try password.data(using: .utf8)?.write(to: certificateFolder.appendingPathComponent("password.txt"))
        try displayName.data(using: .utf8)?.write(to: certificateFolder.appendingPathComponent("name.txt"))
        
        return candidate
    }
    
    func deleteCertificate(folderName: String) throws {
        let certificateFolder = certificatesDirectory.appendingPathComponent(folderName)
        try fileManager.removeItem(at: certificateFolder)
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

struct CertificateView: View {
    @State private var customCertificates: [CustomCertificate] = []
    @State private var showAddCertificateSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Custom Certificates")) {
                    if customCertificates.isEmpty {
                        Text("No certificates added yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(customCertificates) { cert in
                            Text(cert.displayName)
                        }
                        .onDelete { indices in
                            deleteCertificates(at: indices)
                        }
                    }
                }
            }
            .navigationTitle("Certificate App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddCertificateSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCertificateSheet, onDismiss: {
                customCertificates = CertificateFileManager.shared.loadCertificates()
            }) {
                AddCertificateView()
                    .presentationDetents([.medium])
            }
            .onAppear {
                customCertificates = CertificateFileManager.shared.loadCertificates()
            }
        }
    }
    
    private func deleteCertificates(at indices: IndexSet) {
        for index in indices {
            let cert = customCertificates[index]
            try? CertificateFileManager.shared.deleteCertificate(folderName: cert.folderName)
        }
        customCertificates = CertificateFileManager.shared.loadCertificates()
    }
}

struct AddCertificateView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var p12File: CertificateFileItem?
    @State private var provFile: CertificateFileItem?
    @State private var password = ""
    @State private var activeSheet: CertificatePickerKind?
    @State private var isChecking = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Files")) {
                    Button(action: { activeSheet = .p12 }) {
                        HStack {
                            Image(systemName: "lock.doc.fill")
                                .foregroundColor(.blue)
                            Text("Import Certificate (.p12) File")
                            Spacer()
                            if let p12File = p12File {
                                Text(p12File.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isChecking)
                    
                    Button(action: { activeSheet = .prov }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.blue)
                            Text("Import Provisioning (.mobileprovision) File")
                            Spacer()
                            if let provFile = provFile {
                                Text(provFile.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isChecking)
                }
                
                Section(header: Text("Password")) {
                    SecureField("Enter Password", text: $password)
                        .disabled(isChecking)
                    Text("Enter the password for the certificate. Leave it blank if there is no password needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            .navigationTitle("New Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") {
                        dismiss()
                    }
                    .disabled(isChecking)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveCertificate()
                        }
                        .disabled(p12File == nil || provFile == nil)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheetType in
                CertificateDocumentPicker(kind: sheetType) { url in
                    if sheetType == .p12 {
                        p12File = CertificateFileItem(name: url.lastPathComponent, url: url)
                    } else {
                        provFile = CertificateFileItem(name: url.lastPathComponent, url: url)
                    }
                    errorMessage = ""
                }
            }
            .onChange(of: password) { _ in
                errorMessage = ""
            }
        }
    }
    
    private func saveCertificate() {
        guard let p12URL = p12File?.url, let provURL = provFile?.url else { return }
        
        isChecking = true
        errorMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let p12Data = try Data(contentsOf: p12URL)
                let provData = try Data(contentsOf: provURL)
                
                let result = CertificatesManager.check(p12Data: p12Data, password: password, mobileProvisionData: provData)
                
                var dispatchError: String?
                switch result {
                case .success(.success):
                    // Get dynamic name
                    let displayName = CertificatesManager.getCertificateName(p12Data: p12Data, password: password) ?? "Custom Certificate"
                    
                    // Save
                    _ = try CertificateFileManager.shared.saveCertificate(p12Data: p12Data, provData: provData, password: password, displayName: displayName)
                case .success(.incorrectPassword):
                    dispatchError = "Incorrect Password"
                case .success(.noMatch):
                    dispatchError = "P12 and MobileProvision do not match"
                case .failure(let error):
                    dispatchError = "Error: \(error.localizedDescription)"
                }
                
                DispatchQueue.main.async {
                    isChecking = false
                    if let err = dispatchError {
                        errorMessage = err
                    } else {
                        dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isChecking = false
                    errorMessage = "Failed to read files or save: \(error.localizedDescription)"
                }
            }
        }
    }
}