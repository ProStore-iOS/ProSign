import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import ZsignSwift

// MARK: - Small models
struct FileItem {
    var url: URL?
    var name: String { url?.lastPathComponent ?? "" }
}

struct Credit: Identifiable {
    var id = UUID()
    var name: String
    var role: String
    var profileURL: URL
    var avatarURL: URL
}

// MARK: - App
@main
struct ZsignOnDeviceApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

// MARK: - Main tab view
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationView {
                SignerView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Image(systemName: "hammer")
                Text("Signer")
            }

            NavigationView {
                AboutView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Image(systemName: "info.circle")
                Text("About")
            }
        }
    }
}

// MARK: - About view
struct AboutView: View {
    // credits data
    private let credits: [Credit] = [
        Credit(
            name: "zhlynn",
            role: "Original zsign",
            profileURL: URL(string: "https://github.com/zhlynn")!,
            avatarURL: URL(string: "https://github.com/zhlynn.png")!
        ),
        Credit(
            name: "Khcrysalis",
            role: "Zsign-Package (fork)",
            profileURL: URL(string: "https://github.com/khcrysalis")!,
            avatarURL: URL(string: "https://github.com/khcrysalis.png")!
        ),
        Credit(
            name: "SuperGamer474",
            role: "Developer",
            profileURL: URL(string: "https://github.com/SuperGamer474")!,
            avatarURL: URL(string: "https://github.com/SuperGamer474.png")!
        )
    ]

    private var appIconURL: URL? {
        URL(string: "https://raw.githubusercontent.com/ProStore-iOS/ProStore/main/Sources/prostore/Assets.xcassets/AppIcon.appiconset/Icon-1024.png")
    }

    // Only show the short version string (e.g. "1.1.0") to avoid trailing build numbers like "(6)"
    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        List {
            VStack(spacing: 8) {
                if let url = appIconURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(radius: 6)
                        } else if phase.error != nil {
                            // fallback
                            Image(systemName: "app.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView()
                                .frame(width: 80, height: 80)
                        }
                    }
                }

                Text("ProStore")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(versionString)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .listRowInsets(EdgeInsets())

            Section(header: Text("Credits")) {
                ForEach(credits) { c in
                    CreditRow(credit: c)
                }
            }

            // optional sponsors or other sections can go here
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("About")
    }
}

struct CreditRow: View {
    let credit: Credit
    @Environment(\.openURL) var openURL

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: credit.avatarURL) { phase in
                if let img = phase.image {
                    img
                        .resizable()
                        .scaledToFill()
                } else if phase.error != nil {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(UIColor.separator), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.name)
                    .font(.body)
                Text(credit.role)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                openURL(credit.profileURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 8)
    }
}

// MARK: - SignerView (your original ContentView moved here)
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

    // --- runSign same as your original; adapted to compile in this struct scope
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

// MARK: - DocumentPicker wrapper (same as yours)
struct DocumentPicker: UIViewControllerRepresentable {
    var kind: SignerView.PickerKind
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

// MARK: - ActivityView wrapper
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}