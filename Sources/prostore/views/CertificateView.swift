import SwiftUI
import UniformTypeIdentifiers

struct CertificateView: View {
    @StateObject private var officialManager = OfficialCertificateManager()
    
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var customStatusMessage = ""
    @State private var showPickerFor: PickerKind? = nil
    
    @State private var showAllOfficial = false

    var body: some View {
        NavigationStack {
            Form {
                // Official Certificates Section
                Section(header: Text("Official Certificates")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    Text("Thanks to loyahdev!")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(.secondary)
                    
                    if let featured = officialManager.featuredCert {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(featured.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(featured.type.rawValue)
                                .font(.caption)
                                .foregroundColor(featured.type == .signed ? .green : .orange)
                            Button(action: { Task { await officialManager.checkCert(featured) } }) {
                                Text("Check This One")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(officialManager.isProcessing ? Color.gray : Color.green.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(officialManager.isProcessing)
                            if officialManager.isProcessing {
                                ProgressView("Checking...")
                                    .scaleEffect(0.8)
                            }
                            Text(officialManager.currentStatus)
                                .font(.caption)
                                .foregroundColor(officialManager.currentStatus.contains("Success") ? .green : officialManager.currentStatus.isEmpty ? .primary : .red)
                                .animation(.easeInOut(duration: 0.3), value: officialManager.currentStatus)
                        }
                        .padding(.vertical, 4)
                    } else if !officialManager.certs.isEmpty {
                        Text("No featured cert right now—check the full list!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No certificates found :(")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: { showAllOfficial = true }) {
                        HStack {
                            Spacer()
                            Text("More Certificates")
                                .font(.body)
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
                
                // Custom Certificate Section
                Section(header: Text("Custom Certificate")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    // P12 picker
                    HStack {
                        Image(systemName: "lock.doc.fill")
                            .foregroundColor(.blue)
                        Text("P12")
                        Spacer()
                        Text(p12.name.isEmpty ? "No file selected" : p12.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                        Button(action: { showPickerFor = .p12 }) {
                            Text("Pick")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)

                    // MobileProvision picker
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.blue)
                        Text("MobileProvision")
                        Spacer()
                        Text(prov.name.isEmpty ? "No file selected" : prov.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                        Button(action: { showPickerFor = .prov }) {
                            Text("Pick")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)

                    // Password field
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.blue)
                        SecureField("P12 Password", text: $p12Password)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button(action: checkCustomStatus) {
                        HStack {
                            Spacer()
                            Text("Check Status")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(isProcessing || p12.url == nil || prov.url == nil ? Color.gray : Color.blue)
                                .cornerRadius(10)
                                .shadow(radius: 2)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || p12.url == nil || prov.url == nil)
                    .scaleEffect(isProcessing ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isProcessing)
                }
                .padding(.vertical, 8)

                Section(header: Text("Custom Result")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(customStatusMessage)
                            .foregroundColor(customStatusMessage == "Success!" ? .green : customStatusMessage.isEmpty ? .primary : .red)
                            .animation(.easeIn, value: customStatusMessage)
                    }
                }
            }
            .navigationTitle("Certificate App")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.blue)
            .task {
                await officialManager.loadCerts()
            }
        }
        .sheet(item: $showPickerFor, onDismiss: nil) { kind in
            DocumentPicker(kind: kind, onPick: { url in
                switch kind {
                case .p12:
                    p12.url = url
                    p12.name = url.lastPathComponent
                case .prov:
                    prov.url = url
                    prov.name = url.lastPathComponent
                }
            })
        }
        .sheet(isPresented: $showAllOfficial) {
            NavigationStack {
                List {
                    ForEach(officialManager.certs) { cert in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cert.name)
                                .font(.headline)
                            Text(cert.type.rawValue)
                                .font(.caption)
                                .foregroundColor(cert.type == .signed ? .green : .orange)
                            Button(action: {
                                Task { await officialManager.checkCert(cert) }
                            }) {
                                Text("Check")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(officialManager.isProcessing ? Color.gray : Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .disabled(officialManager.isProcessing)
                            if officialManager.isProcessing {
                                ProgressView("Checking...")
                                    .scaleEffect(0.7)
                            }
                            Text(officialManager.currentStatus)
                                .font(.caption)
                                .foregroundColor(officialManager.currentStatus.contains("Success") ? .green : officialManager.currentStatus.isEmpty ? .primary : .red)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .navigationTitle("All Certificates")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    private func checkCustomStatus() {
        guard let p12URL = p12.url, let provURL = prov.url else {
            customStatusMessage = "P12 and MobileProvision do not match"
            return
        }

        isProcessing = true
        customStatusMessage = "Checking..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let p12Data = try Data(contentsOf: p12URL)
                let provData = try Data(contentsOf: provURL)

                let result = CertificatesManager.check(p12Data: p12Data, password: p12Password, mobileProvisionData: provData)

                DispatchQueue.main.async {
                    isProcessing = false
                    switch result {
                    case .success(.incorrectPassword):
                        customStatusMessage = "Incorrect Password"
                    case .success(.noMatch):
                        customStatusMessage = "P12 and MobileProvision do not match"
                    case .success(.success):
                        customStatusMessage = "Success!"
                    case .failure(let err):
                        print("Custom check failed: \(err)")
                        customStatusMessage = "P12 and MobileProvision do not match"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    print("Custom file read error: \(error)")
                    customStatusMessage = "P12 and MobileProvision do not match"
                }
            }
        }
    }
}