// views/CertificateView.swift
// Put this file under views/ in your project

import SwiftUI
import UniformTypeIdentifiers

struct CertificateView: View {
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var statusMessage = "" // will hold exactly one of: "Incorrect Password", "P12 and MOBILEPROVISION do not match", "Success!"
    @State private var showPickerFor: PickerKind? = nil

    var body: some View {
        Form {
            Section(header: Text("Inputs")) {
                HStack {
                    Text("P12:")
                    Spacer()
                    Text(p12.name.isEmpty ? "" : p12.name).foregroundColor(.secondary)
                    Button("Pick") {
                        showPickerFor = .p12
                    }
                }
                HStack {
                    Text("MobileProvision:")
                    Spacer()
                    Text(prov.name.isEmpty ? "" : prov.name).foregroundColor(.secondary)
                    Button("Pick") {
                        showPickerFor = .prov
                    }
                }
                SecureField("P12 Password", text: $p12Password)
            }

            Section {
                Button(action: checkStatus) {
                    HStack {
                        Spacer()
                        Text("Check Status").bold()
                        Spacer()
                    }
                }
                .disabled(isProcessing || p12.url == nil || prov.url == nil)
            }

            Section(header: Text("Result")) {
                Text(statusMessage).foregroundColor(.primary)
            }
        }
        .navigationTitle("Certificates")
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
            statusMessage = "P12 and MOBILEPROVISION do not match"
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
                        statusMessage = "P12 and MOBILEPROVISION do not match" // EXACT text requested
                    case .success(.success):
                        statusMessage = "Success!" // EXACT text requested
                    case .failure(let err):
                        // If there was an unexpected error, surface a no-match (safe) or show error (dev)
                        // We'll show no-match so user gets one of the three expected messages; but log the error.
                        print("Certificates check failed: \(err)")
                        statusMessage = "P12 and MOBILEPROVISION do not match"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    // If the password is wrong we already catch that above. Reading files failed -> show no-match
                    print("File read error: \(error)")
                    statusMessage = "P12 and MOBILEPROVISION do not match"
                }
            }
        }
    }
}