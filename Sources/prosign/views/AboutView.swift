// AboutView.swift
import SwiftUI
import Security

struct Credit: Identifiable {
    var id = UUID()
    var name: String
    var role: String
    var profileURL: URL
    var avatarURL: URL
}

@MainActor
final class SigningInfoProvider: ObservableObject {
    @Published var certCommonName: String = "Unknown"
    @Published var certExpiry: Date? = nil

    @Published var provName: String = "Unknown"
    @Published var provExpiry: Date? = nil

    @Published var errorMessage: String? = nil

    init() {
        Task { await fetchAll() }
    }

    func fetchAll() async {
        fetchSigningCertificate()
        fetchEmbeddedProvision()
    }

    // MARK: - Certificate (from code signature)
    private func fetchSigningCertificate() {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let codeUnwrapped = code else {
            self.errorMessage = "Could not read code object"
            return
        }

        var signingInfoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(codeUnwrapped, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfoRef)
        if infoStatus != errSecSuccess {
            // Try with empty flags if the constant isn't available
            let _ = SecCodeCopySigningInformation(codeUnwrapped, [], &signingInfoRef)
        }

        guard let signingInfo = signingInfoRef as? [String: Any],
              let certs = signingInfo[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let firstCert = certs.first
        else {
            self.errorMessage = "No certificate in signing info"
            return
        }

        // Common name / subject summary
        if let name = SecCertificateCopySubjectSummary(firstCert) as String? {
            self.certCommonName = name
        }

        // NotAfter (expiry)
        var valuesRef: CFDictionary?
        let oids = [kSecOIDX509V1ValidityNotAfter] as CFArray
        if SecCertificateCopyValues(firstCert, oids, &valuesRef) == errSecSuccess,
           let values = valuesRef as? [String: Any],
           let notAfterEntry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let expiry = notAfterEntry[kSecPropertyKeyValue as String] as? Date {
            self.certExpiry = expiry
        } else {
            // fallback: try to parse summary data (rare)
            self.certExpiry = nil
        }
    }

    // MARK: - embedded.mobileprovision (from bundle)
    private func fetchEmbeddedProvision() {
        guard let provPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else {
            // Not found (e.g. App Store app or simulator). Keep defaults.
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: provPath))
            guard let str = String(data: data, encoding: .utf8) else { return }

            // The mobileprovision is a CMS envelope containing a plist. Extract plist XML segment.
            if let startRange = str.range(of: "<?xml"),
               let endRange = str.range(of: "</plist>") {
                let plistString = String(str[startRange.lowerBound...endRange.upperBound])
                if let plistData = plistString.data(using: .utf8) {
                    let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                    if let dict = plist as? [String: Any] {
                        if let name = dict["Name"] as? String {
                            self.provName = name
                        }
                        if let expiry = dict["ExpirationDate"] as? Date {
                            self.provExpiry = expiry
                        } else if let expiryStr = dict["ExpirationDate"] as? String {
                            // Some formats might return a string — try ISO8601
                            let df = ISO8601DateFormatter()
                            if let d = df.date(from: expiryStr) {
                                self.provExpiry = d
                            }
                        }
                    }
                }
            } else {
                // if no plist detected, try scanning bytes for plist start/end bytes
                // (some profiles are binary or slightly different) — try a Data approach
                if let plistRangeStart = data.range(of: Data("<?xml".utf8)),
                   let plistRangeEnd = data.range(of: Data("</plist>".utf8)) {
                    let plistData = data[plistRangeStart.lowerBound...plistRangeEnd.upperBound]
                    let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                    if let dict = plist as? [String: Any] {
                        if let name = dict["Name"] as? String {
                            self.provName = name
                        }
                        if let expiry = dict["ExpirationDate"] as? Date {
                            self.provExpiry = expiry
                        }
                    }
                }
            }
        } catch {
            self.errorMessage = "Failed to read embedded.mobileprovision: \(error.localizedDescription)"
        }
    }
}

struct AboutView: View {
    @StateObject private var signingInfo = SigningInfoProvider()

    private let credits: [Credit] = [
        Credit(
            name: "SuperGamer474",
            role: "Developer",
            profileURL: URL(string: "https://github.com/SuperGamer474")!,
            avatarURL: URL(string: "https://github.com/SuperGamer474.png")!
        ),
        Credit(
            name: "Zhlynn",
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
            name: "Loyahdev",
            role: "iOS Certificates Source",
            profileURL: URL(string: "https://github.com/loyahdev")!,
            avatarURL: URL(string: "https://github.com/loyahdev.png")!
        )
    ]

    private var appIconURL: URL? {
        URL(string: "https://raw.githubusercontent.com/ProStore-iOS/ProSign/main/Sources/prosign/Assets.xcassets/AppIcon.appiconset/Icon-1024.png")
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }

    var body: some View {
        NavigationStack {
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

                    Text("ProSign")
                        .font(.title2)
                        .fontWeight(.semibold)

                    VStack(spacing: 2) {
                        Text("Version \(versionString) (\(buildString))")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        if signingInfo.certCommonName != "Unknown" || signingInfo.certExpiry != nil || signingInfo.provName != "Unknown" || signingInfo.provExpiry != nil {
                            // Show certificate + provisioning info
                            VStack(spacing: 2) {
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Signing certificate")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(signingInfo.certCommonName)
                                            .font(.caption2)
                                            .lineLimit(1)
                                        if let certExpiry = signingInfo.certExpiry {
                                            Text("Expires: \(dateFormatter.string(from: certExpiry))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Expires: Unknown")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.top, 6)

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Provisioning profile")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(signingInfo.provName)
                                            .font(.caption2)
                                            .lineLimit(1)
                                        if let provExpiry = signingInfo.provExpiry {
                                            Text("Expires: \(dateFormatter.string(from: provExpiry))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Expires: Unknown")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }

                                // Show a match / mismatch indicator
                                HStack {
                                    if let certExpiry = signingInfo.certExpiry, let provExpiry = signingInfo.provExpiry {
                                        if Calendar.current.compare(certExpiry, to: provExpiry, toGranularity: .second) == .orderedSame {
                                            Label("Cert and provision match ✅", systemImage: "checkmark.shield")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Label("Cert / provision dates differ ⚠️", systemImage: "exclamationmark.triangle")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                    } else {
                                        // Can't fully compare
                                        Label("Comparison unavailable", systemImage: "questionmark.circle")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.top, 6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowInsets(EdgeInsets())

                Section(header: Text("Credits")) {
                    ForEach(credits) { c in
                        CreditRow(credit: c)
                    }
                }

                if let err = signingInfo.errorMessage {
                    Section(header: Text("Debug")) {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("About")
        }
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
                    .foregroundColor(.primary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 8)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
