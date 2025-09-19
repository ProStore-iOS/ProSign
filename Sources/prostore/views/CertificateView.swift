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
    let fileManager = FileManager.default
    let certificatesDirectory: URL
    
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
    
    func updateCertificate(folderName: String, p12Data: Data, provData: Data, password: String, displayName: String) throws {
        let certificateFolder = certificatesDirectory.appendingPathComponent(folderName)
        guard fileManager.fileExists(atPath: certificateFolder.path) else {
            throw NSError(domain: "CertificateFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Certificate folder not found"])
        }
        
        let p12HashNew = CertificatesManager.sha256Hex(p12Data)
        let provHashNew = CertificatesManager.sha256Hex(provData)
        let passwordHashNew = CertificatesManager.sha256Hex(password.data(using: .utf8) ?? Data())
        
        // Check if new version identical to any other existing (exclude self)
        let existingFolders = try fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for folder in existingFolders {
            if folder == certificateFolder { continue }
            
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
                        throw NSError(domain: "CertificateFileManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "This updated certificate matches another existing one"])
                    }
                } catch {
                    // Skip if can't read existing
                    continue
                }
            }
        }
        
        // Overwrite files
        try p12Data.write(to: certificateFolder.appendingPathComponent("certificate.p12"))
        try provData.write(to: certificateFolder.appendingPathComponent("profile.mobileprovision"))
        try password.data(using: .utf8)?.write(to: certificateFolder.appendingPathComponent("password.txt"))
        try displayName.data(using: .utf8)?.write(to: certificateFolder.appendingPathComponent("name.txt"))
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
    @State private var editingFolder: String? = nil
    @State private var selectedCert: String? = nil
    @State private var showingDeleteAlert = false
    @State private var certToDelete: CustomCertificate?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(customCertificates) { cert in
                        ZStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(cert.displayName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedCert == cert.folderName ? Color.blue : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture {
                                if selectedCert == cert.folderName {
                                    selectedCert = nil
                                    UserDefaults.standard.removeObject(forKey: "selectedCertificateFolder")
                                } else {
                                    selectedCert = cert.folderName
                                    UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
                                }
                            }
                            
                            HStack {
                                Button(action: {
                                    editingFolder = cert.folderName
                                    showAddCertificateSheet = true
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color.white.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    certToDelete = cert
                                    showingDeleteAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color.white.opacity(0.8))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.top, 12)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Certificate App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        editingFolder = nil
                        showAddCertificateSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCertificateSheet, onDismiss: {
                customCertificates = CertificateFileManager.shared.loadCertificates()
                editingFolder = nil
                // Re-check selected after reload
                if let sel = selectedCert, !customCertificates.contains(where: { $0.folderName == sel }) {
                    selectedCert = nil
                    UserDefaults.standard.removeObject(forKey: "selectedCertificateFolder")
                }
            }) {
                AddCertificateView(editingFolder: editingFolder)
                    .presentationDetents([.large])
            }
            .alert("Delete Certificate?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let cert = certToDelete {
                        deleteCertificate(cert)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure? This can't be undone.")
            }
            .onAppear {
                customCertificates = CertificateFileManager.shared.loadCertificates()
                selectedCert = UserDefaults.standard.string(forKey: "selectedCertificateFolder")
                if let sel = selectedCert, !customCertificates.contains(where: { $0.folderName == sel }) {
                    selectedCert = nil
                    UserDefaults.standard.removeObject(forKey: "selectedCertificateFolder")
                }
            }
        }
    }
    
    private func deleteCertificate(_ cert: CustomCertificate) {
        try? CertificateFileManager.shared.deleteCertificate(folderName: cert.folderName)
        customCertificates = CertificateFileManager.shared.loadCertificates()
        if selectedCert == cert.folderName {
            selectedCert = nil
            UserDefaults.standard.removeObject(forKey: "selectedCertificateFolder")
        }
    }
}

struct AddCertificateView: View {
    @Environment(\.dismiss) private var dismiss
    let editingFolder: String?
    
    @State private var p12File: CertificateFileItem?
    @State private var provFile: CertificateFileItem?
    @State private var password = ""
    @State private var activeSheet: CertificatePickerKind?
    @State private var isChecking = false
    @State private var errorMessage = ""
    
    init(editingFolder: String? = nil) {
        self.editingFolder = editingFolder
    }
    
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
            .navigationTitle(editingFolder != nil ? "Edit Certificate" : "New Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("×") {
                        dismiss()
                    }
                    .disabled(isChecking)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
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
            .onAppear {
                if let folder = editingFolder {
                    loadForEdit(folder: folder)
                }
            }
        }
    }
    
    private func loadForEdit(folder: String) {
        let certFolder = CertificateFileManager.shared.certificatesDirectory.appendingPathComponent(folder)
        let p12URL = certFolder.appendingPathComponent("certificate.p12")
        let provURL = certFolder.appendingPathComponent("profile.mobileprovision")
        let passwordURL = certFolder.appendingPathComponent("password.txt")
        
        p12File = CertificateFileItem(name: "certificate.p12", url: p12URL)
        provFile = CertificateFileItem(name: "profile.mobileprovision", url: provURL)
        
        if let pwData = try? Data(contentsOf: passwordURL), let pw = String(data: pwData, encoding: .utf8) {
            password = pw
        }
    }
    
    private func saveCertificate() {
        guard let p12URL = p12File?.url, let provURL = provFile?.url else { return }
        
        isChecking = true
        errorMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var p12Data: Data
                var provData: Data
                if editingFolder != nil {
                    // For edit, files are in app container, no security scope needed
                    p12Data = try Data(contentsOf: p12URL)
                    provData = try Data(contentsOf: provURL)
                } else {
                    // For new, access security-scoped
                    guard p12URL.startAccessingSecurityScopedResource() else {
                        throw NSError(domain: "AccessError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access P12 file"])
                    }
                    defer { p12URL.stopAccessingSecurityScopedResource() }
                    
                    guard provURL.startAccessingSecurityScopedResource() else {
                        throw NSError(domain: "AccessError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot access Provision file"])
                    }
                    defer { provURL.stopAccessingSecurityScopedResource() }
                    
                    p12Data = try Data(contentsOf: p12URL)
                    provData = try Data(contentsOf: provURL)
                }
                
                let result = CertificatesManager.check(p12Data: p12Data, password: password, mobileProvisionData: provData)
                
                var dispatchError: String?
                switch result {
                case .success(.success):
                    let displayName = CertificatesManager.getCertificateName(p12Data: p12Data, password: password) ?? "Custom Certificate"
                    
                    if let folder = editingFolder {
                        try CertificateFileManager.shared.updateCertificate(folderName: folder, p12Data: p12Data, provData: provData, password: password, displayName: displayName)
                    } else {
                        _ = try CertificateFileManager.shared.saveCertificate(p12Data: p12Data, provData: provData, password: password, displayName: displayName)
                    }
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