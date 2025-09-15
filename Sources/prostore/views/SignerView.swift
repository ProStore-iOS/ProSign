import SwiftUI
import UniformTypeIdentifiers

struct SignerView: View {
    @State private var ipa = FileItem()
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var showActivity = false
    @State private var activityURL: URL? = nil
    @State private var showPickerFor: PickerKind?

    enum PickerKind: Identifiable {
        case ipa, p12, prov
        var id: Int {
            switch self {
            case .ipa: return 0
            case .p12: return 1
            case .prov: return 2
            }
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Inputs")) {
                HStack {
                    Text("IPA:")
                    Spacer()
                    Text(ipa.name.isEmpty ? "" : ipa.name).foregroundColor(.secondary)
                    Button("Pick") { showPickerFor = .ipa }
                }
                HStack {
                    Text("P12:")
                    Spacer()
                    Text(p12.name.isEmpty ? "" : p12.name).foregroundColor(.secondary)
                    Button("Pick") { showPickerFor = .p12 }
                }
                HStack {
                    Text("MobileProvision:")
                    Spacer()
                    Text(prov.name.isEmpty ? "" : prov.name).foregroundColor(.secondary)
                    Button("Pick") { showPickerFor = .prov }
                }
                SecureField("P12 Password", text: $p12Password)
            }

            Section {
                Button(action: runSign) {
                    HStack {
                        Spacer()
                        Text("Sign IPA").bold()
                        Spacer()
                    }
                }
                .disabled(isProcessing || ipa.url == nil || p12.url == nil || prov.url == nil)
            }

            Section(header: Text("Status")) {
                Text(progressMessage).foregroundColor(.primary)
            }
        }
        .navigationTitle("Signer")
        .sheet(item: $showPickerFor, onDismiss: nil) { kind in
            DocumentPicker(kind: kind, onPick: { url in
                switch kind {
                case .ipa: ipa.url = url
                case .p12: p12.url = url
                case .prov: prov.url = url
                }
            })
        }
        .sheet(isPresented: $showActivity) {
            if let u = activityURL {
                ActivityView(url: u)
            } else {
                Text("No file to share")
            }
        }
    }

    func runSign() {
        guard let ipaURL = ipa.url, let p12URL = p12.url, let provURL = prov.url else {
            progressMessage = "Pick all input files first 😅"
            return
        }

        isProcessing = true
        progressMessage = "Starting signing process..."

        SigningManager.processSigning(
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