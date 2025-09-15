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

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Inputs")
                            .font(.headline) // Bolder, larger header
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    // IPA picker with icon and truncated file name
                    HStack {
                        Image(systemName: "doc.fill") // Added SF Symbol
                            .foregroundColor(.blue)
                        Text("IPA")
                        Spacer()
                        Text(ipa.name.isEmpty ? "No file selected" : ipa.name)
                            .font(.caption) // Smaller font for file name
                            .lineLimit(1) // Truncate long names
                            .foregroundColor(.secondary)
                        Button(action: { showPickerFor = .ipa }) {
                            Text("Pick")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1)) // Subtle button background
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4) // More spacing

                    // P12 picker with icon
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

                    // MobileProvision picker with icon
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

                    // Password field with secure icon
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.blue)
                        SecureField("P12 Password", text: $p12Password)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button(action: runSign) {
                        HStack {
                            Spacer()
                            Text("Sign IPA")
                                .font(.headline) // Bolder text
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(isProcessing || ipa.url == nil || p12.url == nil || prov.url == nil ? Color.gray : Color.blue) // Dynamic color
                                .cornerRadius(10)
                                .shadow(radius: 2) // Subtle shadow
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || ipa.url == nil || p12.url == nil || prov.url == nil)
                    .scaleEffect(isProcessing ? 0.95 : 1.0) // Subtle animation when processing
                    .animation(.easeInOut(duration: 0.2), value: isProcessing) // Smooth animation
                }
                .padding(.vertical, 8)

                Section(header: Text("Status")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    HStack {
                        if isProcessing {
                            ProgressView() // Spinner for processing
                                .padding(.trailing, 8)
                        }
                        Text(progressMessage)
                            .foregroundColor(progressMessage.contains("Error") ? .red : progressMessage.contains("Done") ? .green : .primary) // Color based on status
                            .animation(.easeIn, value: progressMessage) // Fade animation for status changes
                    }
                }
            }
            .navigationTitle("ProStore Signer")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.blue) // Custom accent color for the app
        }
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
                    .foregroundColor(.red)
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