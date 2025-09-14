import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation // ZipFoundation
import ZsignSwift

struct FileItem {
    var url: URL?
    var name: String { url?.lastPathComponent ?? "" }
}

@main
struct ZsignOnDeviceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var ipa = FileItem()
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var message = ""
    @State private var showActivity = false
    @State private var activityURL: URL? = nil
    @State private var showPickerFor: PickerKind?
    
    enum PickerKind { case ipa, p12, prov }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Inputs")) {
                    HStack {
                        Text("IPA:")
                        Spacer()
                        Text(ipa.name.isEmpty ? "none" : ipa.name).foregroundColor(.secondary)
                        Button("Pick") { showPickerFor = .ipa }
                    }
                    HStack {
                        Text("P12:")
                        Spacer()
                        Text(p12.name.isEmpty ? "none" : p12.name).foregroundColor(.secondary)
                        Button("Pick") { showPickerFor = .p12 }
                    }
                    HStack {
                        Text("MobileProvision:")
                        Spacer()
                        Text(prov.name.isEmpty ? "none" : prov.name).foregroundColor(.secondary)
                        Button("Pick") { showPickerFor = .prov }
                    }
                    SecureField("P12 Password", text: $p12Password)
                }
                
                Section {
                    Button(action: runSign) {
                        HStack {
                            Spacer()
                            if isProcessing { ProgressView() }
                            Text("Sign IPA").bold()
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || ipa.url == nil || p12.url == nil || prov.url == nil)
                }
                
                Section(header: Text("Status")) {
                    Text(message).foregroundColor(.primary)
                }
            }
            .navigationTitle("Zsign On Device")
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
    }
    
    func runSign() {
        guard let ipaURL = ipa.url, let p12URL = p12.url, let provURL = prov.url else {
            message = "Pick all input files first."
            return
        }
        isProcessing = true
        message = "Working..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let tmp = fm.temporaryDirectory.appendingPathComponent("zsign_ios_\(UUID().uuidString)")
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                
                // copy inputs into tmp
                let localIPA = tmp.appendingPathComponent(ipaURL.lastPathComponent)
                let localP12 = tmp.appendingPathComponent(p12URL.lastPathComponent)
                let localProv = tmp.appendingPathComponent(provURL.lastPathComponent)
                try fm.copyItem(at: ipaURL, to: localIPA)
                try fm.copyItem(at: p12URL, to: localP12)
                try fm.copyItem(at: provURL, to: localProv)
                
                // unzip IPA -> tmp
                let archive = try Archive(url: localIPA, accessMode: .read)
                try archive.extract(to: tmp)
                
                // find Payload/*.app
                let payload = tmp.appendingPathComponent("Payload")
                guard fm.fileExists(atPath: payload.path) else {
                    throw NSError(domain: "ZsignOnDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Payload not found"])
                }
                let contents = try fm.contentsOfDirectory(atPath: payload.path)
                guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                    throw NSError(domain: "ZsignOnDevice", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle in Payload"])
                }
                let appDir = payload.appendingPathComponent(appName)
                
                // Call Zsign.swift package sign API
                DispatchQueue.main.async { message = "Signing \(appName)..." }
                
                // NOTE: match your Zsign API exactly. This call mirrors the wrapper you posted earlier:
                let ok = ZsignSwift.sign(
                    appPath: appDir.path,
                    provisionPath: localProv.path,
                    p12Path: localP12.path,
                    p12Password: p12Password,
                    entitlementsPath: "", // optional
                    customIdentifier: "",
                    customName: "",
                    customVersion: "",
                    adhoc: false,
                    removeProvision: false,
                    completion: nil
                )
                
                guard ok else {
                    throw NSError(domain: "ZsignOnDevice", code: 3, userInfo: [NSLocalizedDescriptionKey: "Zsign.sign returned false"])
                }
                
                // Zsign usually writes changes in-place inside the .app. Rezip Payload -> signed IPA
                let signedIpa = tmp.appendingPathComponent("signed_\(appName).ipa")
                // create archive with Payload directory
                try fm.createDirectory(at: signedIpa.deletingLastPathComponent(), withIntermediateDirectories: true)
                let writeArchive = try Archive(url: signedIpa, accessMode: .create)
                
                // recursively add Payload
                let enumerator = fm.enumerator(at: payload, includingPropertiesForKeys: nil)!
                for case let file as URL in enumerator {
                    let relative = file.path.replacingOccurrences(of: tmp.path + "/", with: "")
                    if file.hasDirectoryPath {
                        try writeArchive.addEntry(with: relative + "/", type: .directory, uncompressedSize: 0, compressionMethod: .deflate) // directories recorded
                    } else {
                        let data = try Data(contentsOf: file)
                        try writeArchive.addEntry(with: relative, type: .file, uncompressedSize: UInt32(data.count), compressionMethod: .deflate, provider: { (position, size) -> Data in
                            return data.subdata(in: Int(position)..<Int(position + size))
                        })
                    }
                }
                
                // share file (move to Documents to be easily accessible)
                let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                let outURL = docs.appendingPathComponent("signed_\(UUID().uuidString).ipa")
                if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
                try fm.copyItem(at: signedIpa, to: outURL)
                
                DispatchQueue.main.async {
                    activityURL = outURL
                    showActivity = true
                    message = "Done — signed IPA ready to share!"
                    isProcessing = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    message = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

// DocumentPicker wrapper for picking any file types
struct DocumentPicker: UIViewControllerRepresentable {
    var kind: ContentView.PickerKind
    var onPick: (URL) -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.item] // let user pick any file; could refine UTType.zip / ipa mimetype
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { parent = p }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let u = urls.first else { return }
            parent.onPick(u)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}