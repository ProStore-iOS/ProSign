import SwiftUI
import UniformTypeIdentifiers

struct CertificateView: View {
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var statusMessage = "" // will hold exactly one of: "Incorrect Password", "P12 and Mobileprovison do not match", "Success!"
    @State private var showPickerFor: PickerKind? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Inputs")
                            .font(.headline) // Bolder, larger header
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    // P12 picker with icon and truncated file name
                    HStack {
                        Image(systemName: "lock.doc.fill") // Added SF Symbol
                            .foregroundColor(.blue)
                        Text("P12")
                        Spacer()
                        Text(p12.name.isEmpty ? "No file selected" : p12.name)
                            .font(.caption) // Smaller font for file name
                            .lineLimit(1) // Truncate long names
                            .foregroundColor(.secondary)
                        Button(action: { showPickerFor = .p12 }) {
                            Text("Pick")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1)) // Subtle button background
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4) // More spacing

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
                    Button(action: checkStatus) {
                        HStack {
                            Spacer()
                            Text("Check Status")
                                .font(.headline) // Bolder text
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(isProcessing || p12.url == nil || prov.url == nil ? Color.gray : Color.blue) // Dynamic color
                                .cornerRadius(10)
                                .shadow(radius: 2) // Subtle shadow
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || p12.url == nil || prov.url == nil)
                    .scaleEffect(isProcessing ? 0.95 : 1.0) // Subtle animation when processing
                    .animation(.easeInOut(duration: 0.2), value: isProcessing) // Smooth animation
                }
                .padding(.vertical, 8)

                Section(header: Text("Result")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    HStack {
                        if isProcessing {
                            ProgressView() // Spinner for processing
                                .padding(.trailing, 8)
                        }
                        Text(statusMessage)
                            .foregroundColor(statusMessage == "Success!" ? .green : statusMessage.isEmpty ? .primary : .red) // Green for success, red for errors
                            .animation(.easeIn, value: statusMessage) // Fade animation for status changes
                    }
                }
            }
            .navigationTitle("Certificate Checker")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.blue) // Custom accent color
        }
        .sheet(item: $showPickerFor, onDismiss: nil) { kind in
            DocumentPicker(kind: kind, onPick: { url in
                switch kind {
                case .ipa: break // not used here
                case .p12: p12.url = url
                case .prov: prov.url = url
                }
            })
        }
    }

    private func checkStatus() {
        guard let p12URL = p12.url, let provURL = prov.url else {
            statusMessage = "P12 and Mobileprovison do not match"
            return
        }

        isProcessing = true
        statusMessage = "Checking..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let p12Data = try Data(contentsOf: p12URL)
                let provData = try Data(contentsOf: provURL)

                let result = CertificatesManager.check(p12Data: p12Data, password: p12Password, mobileProvisionData: provData)

                DispatchQueue.main.async {
                    isProcessing = false
                    switch result {
                    case .success(.incorrectPassword):
                        statusMessage = "Incorrect Password" // EXACT text requested
                    case .success(.noMatch):
                        statusMessage = "P12 and Mobileprovison do not match" // EXACT text requested
                    case .success(.success):
                        statusMessage = "Success!" // EXACT text requested
                    case .failure(let err):
                        // If there was an unexpected error, surface a no-match (safe) or show error (dev)
                        // We'll show no-match so user gets one of the three expected messages; but log the error.
                        print("Certificates check failed: \(err)")
                        statusMessage = "P12 and Mobileprovison do not match"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    // If the password is wrong we already catch that above. Reading files failed -> show no-match
                    print("File read error: \(error)")
                    statusMessage = "P12 and Mobileprovison do not match"
                }
            }
        }
    }
}