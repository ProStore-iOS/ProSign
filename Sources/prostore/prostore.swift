import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
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
                .navigationViewStyle(StackNavigationViewStyle()) // Fix iPad sidebar bug
        }
    }
}

struct ContentView: View {
    @State private var ipa = FileItem()
    @State private var p12 = FileItem()
    @State private var prov = FileItem()
    @State private var p12Password = ""
    @State private var isProcessing = false
    @State private var progressMessage = "Idle 😎"
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
                            if isProcessing { ProgressView(progressMessage) }
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
            .navigationTitle("Zsign On Device")
            .navigationViewStyle(StackNavigationViewStyle()) // Fix iPad sidebar issue
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
            progressMessage = "Pick all input files first 😅"
            return
        }

        isProcessing = true
        progressMessage = "Preparing files 📂"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let tmpRoot = fm.temporaryDirectory.appendingPathComponent("zsign_ios_\(UUID().uuidString)")
                let inputs = tmpRoot.appendingPathComponent("inputs")
                let work = tmpRoot.appendingPathComponent("work")
                try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
                try fm.createDirectory(at: work, withIntermediateDirectories: true)

                // Copy inputs
                let localIPA = inputs.appendingPathComponent(ipaURL.lastPathComponent)
                let localP12 = inputs.appendingPathComponent(p12URL.lastPathComponent)
                let localProv = inputs.appendingPathComponent(provURL.lastPathComponent)

                [localIPA, localP12, localProv].forEach { if fm.fileExists(atPath: $0.path) { try? fm.removeItem(at: $0) } }

                try fm.copyItem(at: ipaURL, to: localIPA)
                try fm.copyItem(at: p12URL, to: localP12)
                try fm.copyItem(at: provURL, to: localProv)

                DispatchQueue.main.async { progressMessage = "Unzipping IPA 🔓" }

                // Unzip IPA -> work/
                let archive = try Archive(url: localIPA, accessMode: .read)
                for entry in archive {
                    let dest = work.appendingPathComponent(entry.path)
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if entry.type == .directory {
                        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                    } else {
                        try archive.extract(entry, to: dest)
                    }
                }

                // Locate Payload/*.app
                let payload = work.appendingPathComponent("Payload")
                guard fm.fileExists(atPath: payload.path) else {
                    throw NSError(domain: "ZsignOnDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Payload not found"])
                }
                let contents = try fm.contentsOfDirectory(atPath: payload.path)
                guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                    throw NSError(domain: "ZsignOnDevice", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle in Payload"])
                }
                let appDir = payload.appendingPathComponent(appName)

                DispatchQueue.main.async { progressMessage = "Signing \(appName) ✍️" }

                // Zsign async
                DispatchQueue.main.async {
                    Zsign.sign(
                        appPath: appDir.relativePath,
                        provisionPath: localProv.path,
                        p12Path: localP12.path,
                        p12Password: p12Password,
                        entitlementsPath: "",
                        removeProvision: false,
                        completion: { _, error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    progressMessage = "Signing failed ❌: \(error.localizedDescription)"
                                    isProcessing = false
                                    return
                                }

                                progressMessage = "Zipping signed IPA 📦"
                                do {
                                    let signedIpa = tmpRoot.appendingPathComponent("signed_\(UUID().uuidString).ipa")
                                    let writeArchive = try Archive(url: signedIpa, accessMode: .create)

                                    let enumerator = fm.enumerator(at: work, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil)!
                                    var directories: [URL] = []
                                    var filesList: [URL] = []
                                    for case let file as URL in enumerator {
                                        if file == work { continue }
                                        let isDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? file.hasDirectoryPath
                                        if isDir { directories.append(file) } else { filesList.append(file) }
                                    }
                                    directories.sort { $0.path.count < $1.path.count }
                                    let base = work
                                    for dir in directories {
                                        let relative = dir.path.replacingOccurrences(of: base.path + "/", with: "")
                                        let entryPath = relative.hasSuffix("/") ? relative : relative + "/"
                                        try writeArchive.addEntry(with: entryPath, relativeTo: base, compressionMethod: .none)
                                    }
                                    for file in filesList {
                                        let relative = file.path.replacingOccurrences(of: base.path + "/", with: "")
                                        try writeArchive.addEntry(with: relative, relativeTo: base, compressionMethod: .deflate)
                                    }

                                    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                                    let outURL = docs.appendingPathComponent("signed_\(UUID().uuidString).ipa")
                                    if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
                                    try fm.copyItem(at: signedIpa, to: outURL)

                                    activityURL = outURL
                                    showActivity = true
                                    progressMessage = "Done! ✅ IPA ready to share 🎉"
                                    isProcessing = false

                                    try? fm.removeItem(at: tmpRoot) // cleanup

                                } catch {
                                    progressMessage = "Error during zipping ❌: \(error.localizedDescription)"
                                    isProcessing = false
                                }
                            }
                        }
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    progressMessage = "Error ❌: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

// DocumentPicker wrapper
struct DocumentPicker: UIViewControllerRepresentable {
    var kind: ContentView.PickerKind
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.item]
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

// ActivityView wrapper
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
