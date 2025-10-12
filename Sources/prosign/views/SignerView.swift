import SwiftUI
import UniformTypeIdentifiers
import ProStoreTools

struct SignerView: View {
    @StateObject private var ipa = FileItem()
    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var showActivity = false
    @State private var activityURL: URL? = nil
    @State private var showPickerFor: PickerKind?
    @State private var selectedCertificateName: String? = nil
    @State private var hasSelectedCertificate: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Inputs")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.top, 8)) {
                // IPA picker with icon and truncated file name
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    Text("IPA")
                    Spacer()
                    Text(ipa.name.isEmpty ? "No file selected" : ipa.name)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                    Button(action: { showPickerFor = .ipa }) {
                        Text("Pick")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
                
                if hasSelectedCertificate, let name = selectedCertificateName {
                    Text("The \(name) certificate will be used. If you wish to select a different certificate, please select a different one on the certificates page.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    Text("No certificate selected. Please add and select one in the Certificates tab.")
                        .foregroundColor(.red)
                        .padding(.vertical, 4)
                }
            }
            Section {
                Button(action: runSign) {
                    HStack {
                        Spacer()
                        Text("Sign IPA")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(isProcessing || ipa.url == nil || !hasSelectedCertificate ? Color.gray : Color.blue)
                            .cornerRadius(10)
                            .shadow(radius: 2)
                        Spacer()
                    }
                }
                .disabled(isProcessing || ipa.url == nil || !hasSelectedCertificate)
                .scaleEffect(isProcessing ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isProcessing)
            }
            .padding(.vertical, 8)
            Section(header: Text("Status")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.top, 8)) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text(progressMessage)
                        .foregroundColor(progressMessage.contains("Error") ? .red : progressMessage.contains("Done") ? .green : .primary)
                        .animation(.easeIn, value: progressMessage)
                }
            }
        }
        .accentColor(.blue)
        .sheet(item: $showPickerFor, onDismiss: nil) { kind in
            DocumentPicker(kind: kind, onPick: { url in
                switch kind {
                case .ipa: ipa.url = url
                default: break
                }
            })
        }
        .sheet(isPresented: $showActivity) {
            if let u = activityURL {
                ActivityView(url: u)
            } else {
                Text("No file to share")
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            loadSelectedCertificate()
        }
    }
    
    private func loadSelectedCertificate() {
        guard let selectedFolder = UserDefaults.standard.string(forKey: "selectedCertificateFolder") else {
            hasSelectedCertificate = false
            return
        }
        
        let certDir = CertificateFileManager.shared.certificatesDirectory.appendingPathComponent(selectedFolder)
        
        do {
            if let nameData = try? Data(contentsOf: certDir.appendingPathComponent("name.txt")),
               let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                selectedCertificateName = name
            } else {
                selectedCertificateName = "Custom Certificate"
            }
            hasSelectedCertificate = true
        } catch {
            hasSelectedCertificate = false
            selectedCertificateName = nil
        }
    }
    
    func runSign() {
        guard let ipaURL = ipa.url else {
            progressMessage = "Pick IPA file first 😅"
            return
        }
        
        guard let selectedFolder = UserDefaults.standard.string(forKey: "selectedCertificateFolder") else {
            progressMessage = "No certificate selected 😅"
            return
        }
        
        let certDir = CertificateFileManager.shared.certificatesDirectory.appendingPathComponent(selectedFolder)
        let p12URL = certDir.appendingPathComponent("certificate.p12")
        let provURL = certDir.appendingPathComponent("profile.mobileprovision")
        let passwordURL = certDir.appendingPathComponent("password.txt")
        
        guard FileManager.default.fileExists(atPath: p12URL.path),
              FileManager.default.fileExists(atPath: provURL.path) else {
            progressMessage = "Error loading certificate files 😅"
            return
        }
        
        let p12Password: String
        if let passwordData = try? Data(contentsOf: passwordURL),
           let passwordStr = String(data: passwordData, encoding: .utf8) {
            p12Password = passwordStr
        } else {
            p12Password = ""
        }
        
        isProcessing = true
        progressMessage = "Starting signing process..."
        ProStoreTools.sign(
            ipaURL: ipaURL,
            p12URL: p12URL,
            provURL: provURL,
            p12Password: p12Password,
            progressUpdate: { message in
                DispatchQueue.main.async {
                    progressMessage = message
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    isProcessing = false
                    switch result {
                    case .success(let signedIPAURL):
                        activityURL = signedIPAURL
                        showActivity = true
                        progressMessage = "Done! ✅ IPA ready to share 🎉"
                    case .failure(let error):
                        progressMessage = "Error ❌: \(error.localizedDescription)"
                    }
                }
            }
        )
    }
}
