// CertificateView.swift
import SwiftUI
import UniformTypeIdentifiers

// Centralized types to avoid redeclaration
struct CertificateFileItem {
    var name: String = ""
    var url: URL?
}

struct CustomCertificate: Identifiable {
    let id = UUID()
    let name: String
    let p12Data: Data
    let provData: Data
    let password: String
    var status: String = ""
    var isProcessing: Bool = false
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
                        ForEach($customCertificates) { $cert in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cert.name)
                                        .font(.headline)
                                    if !cert.status.isEmpty {
                                        Text(cert.status)
                                            .font(.caption)
                                            .foregroundColor(cert.status == "Success!" ? .green : .red)
                                    }
                                }
                                
                                Spacer()
                                
                                if cert.isProcessing {
                                    ProgressView()
                                } else {
                                    Button("Check") {
                                        checkCertificate(certificate: $cert)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Certificate App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddCertificateSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCertificateSheet) {
                AddCertificateView(customCertificates: $customCertificates)
            }
        }
    }
    
    private func checkCertificate(certificate: Binding<CustomCertificate>) {
        certificate.wrappedValue.isProcessing = true
        certificate.wrappedValue.status = "Checking..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CertificatesManager.check(
                p12Data: certificate.wrappedValue.p12Data,
                password: certificate.wrappedValue.password,
                mobileProvisionData: certificate.wrappedValue.provData
            )
            
            DispatchQueue.main.async {
                certificate.wrappedValue.isProcessing = false
                
                switch result {
                case .success(.success):
                    certificate.wrappedValue.status = "Success!"
                case .success(.incorrectPassword):
                    certificate.wrappedValue.status = "Incorrect Password"
                case .success(.noMatch):
                    certificate.wrappedValue.status = "P12 and MobileProvision do not match"
                case .failure:
                    certificate.wrappedValue.status = "Error checking certificate"
                }
            }
        }
    }
}

struct AddCertificateView: View {
    @Binding var customCertificates: [CustomCertificate]
    @Environment(\.dismiss) private var dismiss
    
    @State private var p12File: CertificateFileItem?
    @State private var provFile: CertificateFileItem?
    @State private var password = ""
    
    @State private var activeSheet: CertificatePickerKind?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Files")) {
                    Button(action: { activeSheet = .p12 }) {
                        HStack {
                            Image(systemName: "lock.doc.fill")
                            Text("Import Certificate (.p12) File")
                            Spacer()
                            if let p12File = p12File {
                                Text(p12File.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button(action: { activeSheet = .prov }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Import Provisioning (.mobileprovision) File")
                            Spacer()
                            if let provFile = provFile {
                                Text(provFile.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Password")) {
                    SecureField("Enter Password", text: $password)
                    Text("Enter the password for the certificate. Leave it blank if there is no password needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCertificate()
                    }
                    .disabled(p12File == nil || provFile == nil)
                }
            }
            .sheet(item: $activeSheet) { sheetType in
                CertificateDocumentPicker(kind: sheetType) { url in
                    if sheetType == .p12 {
                        p12File = CertificateFileItem(name: url.lastPathComponent, url: url)
                    } else {
                        provFile = CertificateFileItem(name: url.lastPathComponent, url: url)
                    }
                }
            }
        }
    }
    
    private func saveCertificate() {
        guard let p12File = p12File, 
              let provFile = provFile,
              let p12URL = p12File.url,
              let provURL = provFile.url else { return }
        
        do {
            let p12Data = try Data(contentsOf: p12URL)
            let provData = try Data(contentsOf: provURL)
            
            let newCertificate = CustomCertificate(
                name: p12File.name,
                p12Data: p12Data,
                provData: provData,
                password: password
            )
            
            customCertificates.append(newCertificate)
            dismiss()
        } catch {
            print("Error reading files: \(error)")
        }
    }
}