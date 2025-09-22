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
        var resultCerts: [CustomCertificate] = []
        guard let folders = try? fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        
        for folder in folders {
            let nameURL = folder.appendingPathComponent("name.txt")
            if fileManager.fileExists(atPath: nameURL.path) {
                if let nameData = try? Data(contentsOf: nameURL),
                   let nameString = String(data: nameData, encoding: .utf8) {
                    resultCerts.append(CustomCertificate(displayName: nameString, folderName: folder.lastPathComponent))
                }
            } else {
                // Fallback display name if missing
                resultCerts.append(CustomCertificate(displayName: folder.lastPathComponent, folderName: folder.lastPathComponent))
            }
        }
        
        return resultCerts
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
        
        // Create folder
        var finalName = baseName
        var counter = 1
        var folderURL = certificatesDirectory.appendingPathComponent(finalName)
        while fileManager.fileExists(atPath: folderURL.path) {
            counter += 1
            finalName = "\(baseName)-\(counter)"
            folderURL = certificatesDirectory.appendingPathComponent(finalName)
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        try p12Data.write(to: folderURL.appendingPathComponent("certificate.p12"))
        try provData.write(to: folderURL.appendingPathComponent("profile.mobileprovision"))
        try password.data(using: .utf8)?.write(to: folderURL.appendingPathComponent("password.txt"))
        let displayToWrite = uniqueDisplayName(displayName, excludingFolder: nil)
        try displayToWrite.data(using: .utf8)?.write(to: folderURL.appendingPathComponent("name.txt"))
        
        return finalName
    }
    
    func updateCertificate(folderName: String, p12Data: Data, provData: Data, password: String, displayName: String) throws {
        let certificateFolder = certificatesDirectory.appendingPathComponent(folderName)
        let p12HashNew = CertificatesManager.sha256Hex(p12Data)
        let provHashNew = CertificatesManager.sha256Hex(provData)
        let passwordHashNew = CertificatesManager.sha256Hex(password.data(using: .utf8) ?? Data())
        
        // Prevent accidental duplicate update matching another cert
        let existingFolders = try fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for folder in existingFolders where folder.lastPathComponent != folderName {
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
        let displayToWrite = uniqueDisplayName(displayName, excludingFolder: folderName)
        try displayToWrite.data(using: .utf8)?.write(to: certificateFolder.appendingPathComponent("name.txt"))
    }
    
    func deleteCertificate(folderName: String) throws {
        let certificateFolder = certificatesDirectory.appendingPathComponent(folderName)
        try fileManager.removeItem(at: certificateFolder)
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    // Return a unique display name by appending " 2", " 3", ... if needed.
    // `excludingFolder` lets updateCertificate keep the current folder's name out of the conflict check.
    private func uniqueDisplayName(_ desired: String, excludingFolder: String? = nil) -> String {
        let base = desired.isEmpty ? "Custom Certificate" : desired
        var existingNames = Set<String>()
        if let folders = try? fileManager.contentsOfDirectory(at: certificatesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for folder in folders {
                if folder.lastPathComponent == excludingFolder { continue }
                let nameURL = folder.appendingPathComponent("name.txt")
                if let data = try? Data(contentsOf: nameURL), let s = String(data: data, encoding: .utf8) {
                    existingNames.insert(s)
                } else {
                    // fallback to folder name if name.txt missing
                    existingNames.insert(folder.lastPathComponent)
                }
            }
        }

        if !existingNames.contains(base) {
            return base
        }

        var counter = 2
        while existingNames.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

// MARK: - CertificateView (List + Add/Edit launchers)
struct CertificateView: View {
    @State private var customCertificates: [CustomCertificate] = []
    @State private var showAddCertificateSheet = false
    @State private var editingCertificate: CustomCertificate? = nil   // Used only for edit sheet (.sheet(item:))
    @State private var selectedCert: String? = nil
    @State private var showingDeleteAlert = false
    @State private var certToDelete: CustomCertificate?
    
    var body: some View {
        NavigationStack {
            Form {
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
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedCert == cert.folderName ? Color.blue : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture {
                                // Only allow deselection if there are other certificates available
                                if selectedCert == cert.folderName && customCertificates.count > 1 {
                                    if let nextCert = customCertificates.first(where: { $0.folderName != cert.folderName }) {
                                        selectedCert = nextCert.folderName
                                        UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
                                    }
                                } else {
                                    selectedCert = cert.folderName
                                    UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
                                }
                            }
                            
                            HStack {
                                Button(action: {
                                    // EDIT: trigger identifiable sheet
                                    editingCertificate = cert
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color(.systemGray6).opacity(0.8))
                                        .clipShape(Circle())
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if customCertificates.count > 1 {
                                        certToDelete = cert
                                        showingDeleteAlert = true
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(customCertificates.count > 1 ? .red : .gray)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color(.systemGray6).opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .disabled(customCertificates.count <= 1)
                            }
                            .padding(.top, 12)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGray6))
            .navigationTitle("Certificate App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddCertificateSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            // ADD sheet (new certificate only)
            .sheet(isPresented: $showAddCertificateSheet, onDismiss: {
                reloadCertificatesAndEnsureSelection()
            }) {
                AddCertificateView()
                    .presentationDetents([.large])
            }
            // EDIT sheet (identifiable)
            .sheet(item: $editingCertificate, onDismiss: {
                reloadCertificatesAndEnsureSelection()
            }) { editing in
                AddCertificateView(editingCertificate: editing)
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
                reloadCertificatesAndEnsureSelection()
            }
        }
    }
    
    private func reloadCertificatesAndEnsureSelection() {
        customCertificates = CertificateFileManager.shared.loadCertificates()
        selectedCert = UserDefaults.standard.string(forKey: "selectedCertificateFolder")
        ensureSelection()
    }
    
    private func ensureSelection() {
        if selectedCert == nil || !customCertificates.contains(where: { $0.folderName == selectedCert }) {
            if let firstCert = customCertificates.first {
                selectedCert = firstCert.folderName
                UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
            }
        }
    }
    
    private func deleteCertificate(_ cert: CustomCertificate) {
        try? CertificateFileManager.shared.deleteCertificate(folderName: cert.folderName)
        customCertificates = CertificateFileManager.shared.loadCertificates()
        
        if selectedCert == cert.folderName {
            if let newSelection = customCertificates.first {
                selectedCert = newSelection.folderName
                UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
            } else {
                selectedCert = nil
                UserDefaults.standard.removeObject(forKey: "selectedCertificateFolder")
            }
        }
        ensureSelection()
    }
}

// MARK: - Add / Edit View
struct AddCertificateView: View {
    @Environment(\.dismiss) private var dismiss
    let editingCertificate: CustomCertificate?
    
    @State private var p12File: CertificateFileItem?
    @State private var provFile: CertificateFileItem?
    @State private var password = ""
    @State private var activeSheet: CertificatePickerKind?
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var displayName: String = ""
    @State private var hasLoadedForEdit = false
    
    init(editingCertificate: CustomCertificate? = nil) {
        self.editingCertificate = editingCertificate
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
                
                Section(header: Text("Display Name")) {
                    TextField("Optional Display Name", text: $displayName)
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
            .navigationTitle(editingCertificate != nil ? "Edit Certificate" : "New Certificate")
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
                if let cert = editingCertificate, !hasLoadedForEdit {
                    loadForEdit(cert: cert)
                    hasLoadedForEdit = true
                }
            }
        }
    }
    
    private func loadForEdit(cert: CustomCertificate) {
        let certFolder = CertificateFileManager.shared.certificatesDirectory.appendingPathComponent(cert.folderName)
        let p12URL = certFolder.appendingPathComponent("certificate.p12")
        let provURL = certFolder.appendingPathComponent("profile.mobileprovision")
        let passwordURL = certFolder.appendingPathComponent("password.txt")
        let nameURL = certFolder.appendingPathComponent("name.txt")
        
        p12File = CertificateFileItem(name: "certificate.p12", url: p12URL)
        provFile = CertificateFileItem(name: "profile.mobileprovision", url: provURL)
        
        if let pwData = try? Data(contentsOf: passwordURL), let pw = String(data: pwData, encoding: .utf8) {
            password = pw
        }
        if let nameData = try? Data(contentsOf: nameURL), let nameStr = String(data: nameData, encoding: .utf8) {
            displayName = nameStr
        }
    }

    private func saveCertificate() {
        guard let p12URL = p12File?.url, let provURL = provFile?.url else { return }
        
        isChecking = true
        errorMessage = ""
        
        let workItem: DispatchWorkItem = DispatchWorkItem {
            do {
                var p12Data: Data
                var provData: Data
                var localDisplayName = self.displayName  // Local copy to modify if needed
                if self.editingCertificate != nil {
                    p12Data = try Data(contentsOf: p12URL)
                    provData = try Data(contentsOf: provURL)
                } else {
                    // Call start, but don't guard—proceed to read anyway
                    let p12Scoped = p12URL.startAccessingSecurityScopedResource()
                    let provScoped = provURL.startAccessingSecurityScopedResource()
                    defer {
                        if p12Scoped { p12URL.stopAccessingSecurityScopedResource() }
                        if provScoped { provURL.stopAccessingSecurityScopedResource() }
                    }
                    p12Data = try Data(contentsOf: p12URL)
                    provData = try Data(contentsOf: provURL)
                }
                
                let checkResult = CertificatesManager.check(p12Data: p12Data, password: self.password, mobileProvisionData: provData)
                var dispatchError: String?
                
                switch checkResult {
                case .success(.success):
                    // Generate displayName from cert if not set
                    if localDisplayName.isEmpty {
                        localDisplayName = CertificatesManager.getCertificateName(p12Data: p12Data, password: self.password) ?? "Custom Certificate"
                    }
                    
                    if let folder = self.editingCertificate?.folderName {
                        try CertificateFileManager.shared.updateCertificate(folderName: folder, p12Data: p12Data, provData: provData, password: self.password, displayName: localDisplayName)
                    } else {
                        _ = try CertificateFileManager.shared.saveCertificate(p12Data: p12Data, provData: provData, password: self.password, displayName: localDisplayName)
                    }
                case .success(.incorrectPassword):
                    dispatchError = "Incorrect Password"
                case .success(.noMatch):
                    dispatchError = "P12 and MobileProvision do not match"
                case .failure(let error):
                    dispatchError = "Error: \(error.localizedDescription)"
                }
                
                DispatchQueue.main.async {
                    self.isChecking = false
                    if let err = dispatchError {
                        self.errorMessage = err
                    } else {
                        self.dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    self.errorMessage = "Failed to read files or save: \(error.localizedDescription)"
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
}