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

                // create unique temp root and separate subfolders to avoid collisions
                let tmpRoot = fm.temporaryDirectory.appendingPathComponent("zsign_ios_\(UUID().uuidString)")
                let inputs = tmpRoot.appendingPathComponent("inputs")
                let work = tmpRoot.appendingPathComponent("work")
                try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
                try fm.createDirectory(at: work, withIntermediateDirectories: true)

                // copy inputs into inputs/
                let localIPA = inputs.appendingPathComponent(ipaURL.lastPathComponent)
                let localP12 = inputs.appendingPathComponent(p12URL.lastPathComponent)
                let localProv = inputs.appendingPathComponent(provURL.lastPathComponent)

                // remove destinations if they somehow already exist (defensive)
                if fm.fileExists(atPath: localIPA.path) { try fm.removeItem(at: localIPA) }
                if fm.fileExists(atPath: localP12.path) { try fm.removeItem(at: localP12) }
                if fm.fileExists(atPath: localProv.path) { try fm.removeItem(at: localProv) }

                try fm.copyItem(at: ipaURL, to: localIPA)
                try fm.copyItem(at: p12URL, to: localP12)
                try fm.copyItem(at: provURL, to: localProv)

                // unzip IPA -> work/ (extract each entry to explicit destination to avoid collisions)
                let archive = try Archive(url: localIPA, accessMode: .read)
                for entry in archive {
                    // Build destination URL under `work/` using the entry's path
                    let dest = work.appendingPathComponent(entry.path)
                    // Ensure parent directory exists
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if entry.type == .directory {
                        // create directory
                        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                    } else {
                        // extract file to exact destination
                        try archive.extract(entry, to: dest)
                    }
                }

                // find Payload/*.app inside work/
                let payload = work.appendingPathComponent("Payload")
                guard fm.fileExists(atPath: payload.path) else {
                    throw NSError(domain: "ZsignOnDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Payload not found in IPA"])
                }
                let contents = try fm.contentsOfDirectory(atPath: payload.path)
                guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                    throw NSError(domain: "ZsignOnDevice", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle in Payload"])
                }
                let appDir = payload.appendingPathComponent(appName)

                // Call Zsign.swift package sign API
                DispatchQueue.main.async { message = "Signing \(appName)..." }

                let ok = Zsign.sign(
                    appPath: appDir.path,
                    provisionPath: localProv.path,
                    p12Path: localP12.path,
                    p12Password: p12Password,
                    entitlementsPath: "",
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

                // Rezip Payload -> signed IPA from the `work` folder so relative paths are correct
                let signedIpa = tmpRoot.appendingPathComponent("signed_\(UUID().uuidString).ipa")
                // ensure output folder exists (tmpRoot exists)
                let writeArchive = try Archive(url: signedIpa, accessMode: .create)

                // Walk `work` and collect directories & files
                let enumerator = fm.enumerator(at: work, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil)!
                var directories: [URL] = []
                var filesList: [URL] = []
                for case let file as URL in enumerator {
                    // Skip the work root itself
                    if file == work { continue }
                    let isDirResource = try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? file.hasDirectoryPath
                    if isDirResource {
                        directories.append(file)
                    } else {
                        filesList.append(file)
                    }
                }

                // Sort directories so parents come before children
                directories.sort { $0.path.count < $1.path.count }

                // Base for relative paths is `work`
                let base = work

                // Add directories first (ensure trailing slash)
                for dir in directories {
                    let relative = dir.path.replacingOccurrences(of: base.path + "/", with: "")
                    let entryPath = relative.hasSuffix("/") ? relative : relative + "/"
                    try writeArchive.addEntry(with: entryPath, relativeTo: base, compressionMethod: .none)
                }

                // Add files
                for file in filesList {
                    let relative = file.path.replacingOccurrences(of: base.path + "/", with: "")
                    try writeArchive.addEntry(with: relative, relativeTo: base, compressionMethod: .deflate)
                }

                // Finalise: copy to Documents so user can share
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

                // optional: cleanup tmp (comment out if you want to inspect)
                try? fm.removeItem(at: tmpRoot)

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

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        return vc
    }
    func updateUIViewController(_ uiActivityViewController: UIActivityViewController, context: Context) {}
}
