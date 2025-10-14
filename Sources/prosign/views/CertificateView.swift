import SwiftUI
import UniformTypeIdentifiers
import ProStoreTools

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

// CertStatus stores the optional expiration Date and the raw numeric status returned from checkRevokage
enum CertStatus {
    case loading
    case signed(Date?, Int)   // e.g. (expirationDate, rawStatusNumber)
    case revoked(Date?, Int)  // e.g. (expirationDate, rawStatusNumber)
    case unknown(Int)         // rawStatusNumber for unknown (-1, etc.)
}

extension CertStatus {
    var description: String {
        switch self {
        case .loading:
            return "Status: Loading"
        case .signed(_, let raw):
            return "Status: Signed (\(raw))"
        case .revoked(_, let raw):
            return "Status: Revoked (\(raw))"
        case .unknown(let raw):
            return "Status: Unknown (\(raw))"
        }
    }
    
    var color: Color {
        switch self {
        case .loading:
            return .black
        case .signed:
            return .green
        case .revoked:
            return .red
        case .unknown:
            return .yellow
        }
    }
    
    // Optional: expose expiration date if needed elsewhere
    var expirationDate: Date? {
        switch self {
        case .signed(let date, _):
            return date
        case .revoked(let date, _):
            return date
        default:
            return nil
        }
    }
}

// MARK: - CertificateView (List + Add/Edit launchers)
struct CertificateView: View {
    @State private var customCertificates: [CustomCertificate] = []
    @State private var certStatuses: [String: CertStatus] = [:]
    @State private var showAddCertificateSheet = false
    @State private var editingCertificate: CustomCertificate? = nil // Used only for edit sheet (.sheet(item:))
    @State private var selectedCert: String? = nil
    @State private var showingDeleteAlert = false
    @State private var certToDelete: CustomCertificate?
    @State private var newlyAddedFolder: String? = nil
 
    var body: some View {
        // <-- Removed nested NavigationStack to avoid hiding the title from the parent stack
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(customCertificates) { cert in
                    ZStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(cert.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            if let status = certStatuses[cert.folderName] {
                                Text(status.description)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(status.color)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
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
        .background(Color(.systemGray6))
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
            if let newFolder = newlyAddedFolder {
                selectedCert = newFolder
                UserDefaults.standard.set(selectedCert, forKey: "selectedCertificateFolder")
                newlyAddedFolder = nil
            }
        }) {
            AddCertificateView(onSave: { newlyAddedFolder = $0 })
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
 
    private func reloadCertificatesAndEnsureSelection() {
        customCertificates = CertificateFileManager.shared.loadCertificates()
        selectedCert = UserDefaults.standard.string(forKey: "selectedCertificateFolder")
        ensureSelection()
        checkStatuses()
    }
    
    private func checkStatuses() {
        for cert in customCertificates {
            let folderName = cert.folderName
            certStatuses[folderName] = .loading

            let certDir = CertificateFileManager.shared.certificatesDirectory.appendingPathComponent(folderName)
            let p12URL = certDir.appendingPathComponent("certificate.p12")
            let provURL = certDir.appendingPathComponent("profile.mobileprovision")
            let passwordURL = certDir.appendingPathComponent("password.txt")

            let p12Password: String
            if let passwordData = try? Data(contentsOf: passwordURL),
               let passwordStr = String(data: passwordData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                p12Password = passwordStr
            } else {
                p12Password = ""
            }

            ProStoreTools.checkRevokage(
                p12URL: p12URL,
                provURL: provURL,
                p12Password: p12Password
            ) { status, expirationDate, error in
                DispatchQueue.main.async {
                    // Convert Int32 -> Int ONCE and use rawStatus everywhere
                    let rawStatus = Int(status)

                    let newStatus: CertStatus
                    switch rawStatus {
                    case 0:
                        newStatus = .signed(expirationDate, rawStatus)
                    case 1, 2:
                        newStatus = .revoked(expirationDate, rawStatus)
                    default:
                        newStatus = .unknown(rawStatus)
                    }
                    self.certStatuses[folderName] = newStatus
                }
            }
        }
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
        checkStatuses()
    }
}
// MARK: - Add / Edit View
struct AddCertificateView: View {
    @Environment(\.dismiss) private var dismiss
    let editingCertificate: CustomCertificate?
    let onSave: ((String) -> Void)?
 
    @State private var p12File: CertificateFileItem?
    @State private var provFile: CertificateFileItem?
    @State private var password = ""
    @State private var activeSheet: CertificatePickerKind?
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var displayName: String = ""
    @State private var hasLoadedForEdit = false
 
    init(editingCertificate: CustomCertificate? = nil, onSave: ((String) -> Void)? = nil) {
        self.editingCertificate = editingCertificate
        self.onSave = onSave
    }
 
    var body: some View {
        // Use a NavigationStack inside the sheet so the sheet has its own nav bar
        NavigationStack {
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
        } // NavigationStack
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
                var localDisplayName = self.displayName // Local copy to modify if needed
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
                        localDisplayName = CertificatesManager.getCertificateName(mobileProvisionData: provData) ?? "Custom Certificate"
                    }
                 
                    if let folder = self.editingCertificate?.folderName {
                        try CertificateFileManager.shared.updateCertificate(folderName: folder, p12Data: p12Data, provData: provData, password: self.password, displayName: localDisplayName)
                    } else {
                        let newFolder = try CertificateFileManager.shared.saveCertificate(p12Data: p12Data, provData: provData, password: self.password, displayName: localDisplayName)
                        self.onSave?(newFolder)
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

