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
        await fetchEmbeddedProvisionAndCert()
    }

    /// Reads embedded.mobileprovision, extracts provisioning Name + ExpirationDate,
    /// and also extracts the first DeveloperCertificates entry (DER) and reads its CN + expiry.
    private func fetchEmbeddedProvisionAndCert() async {
        guard let provPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else {
            // Not found: App Store builds and the Simulator typically won't include it.
            self.errorMessage = nil
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: provPath))
            guard let str = String(data: data, encoding: .utf8) else {
                self.errorMessage = "embedded.mobileprovision decoding failed"
                return
            }

            // Extract the plist XML segment out of the CMS envelope
            guard let startRange = str.range(of: "<?xml"),
                  let endRange = str.range(of: "</plist>") else {
                // fallback: try to find plist bytes inside the raw data
                if let start = data.range(of: Data("<?xml".utf8)),
                   let end = data.range(of: Data("</plist>".utf8)) {
                    let plistData = data[start.lowerBound...end.upperBound]
                    try parseProvisionPlist(Data(plistData))
                } else {
                    self.errorMessage = "No plist found inside embedded.mobileprovision"
                }
                return
            }

            let plistString = String(str[startRange.lowerBound...endRange.upperBound])
            if let plistData = plistString.data(using: .utf8) {
                try parseProvisionPlist(plistData)
            } else {
                self.errorMessage = "Failed to re-encode plist string"
            }
        } catch {
            self.errorMessage = "Failed to read embedded.mobileprovision: \(error.localizedDescription)"
        }
    }

    private func parseProvisionPlist(_ plistData: Data) throws {
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        guard let dict = plist as? [String: Any] else { return }

        // Provisioning info
        if let name = dict["Name"] as? String {
            self.provName = name
        }
        if let expiry = dict["ExpirationDate"] as? Date {
            self.provExpiry = expiry
        } else if let expiryStr = dict["ExpirationDate"] as? String {
            // attempt ISO8601 parse as a fallback
            let df = ISO8601DateFormatter()
            if let d = df.date(from: expiryStr) { self.provExpiry = d }
        }

        // DeveloperCertificates -> array of DER blobs (NSData)
        if let devCerts = dict["DeveloperCertificates"] as? [Any], !devCerts.isEmpty {
            // Try the first certificate
            for raw in devCerts {
                if let certData = raw as? Data {
                    processCertificateDER(certData)
                    break
                } else if let nsdata = raw as? NSData {
                    processCertificateDER(nsdata as Data)
                    break
                } else if let b64 = raw as? String, let decoded = Data(base64Encoded: b64) {
                    processCertificateDER(decoded)
                    break
                }
            }
        } else {
            // No developer certs in the profile (possible for certain distribution types)
        }
    }

    private func processCertificateDER(_ der: Data) {
        guard let secCert = SecCertificateCreateWithData(nil, der as CFData) else {
            self.errorMessage = "Failed to create SecCertificate from DER"
            return
        }

        // Common name / summary (works on iOS)
        if let name = SecCertificateCopySubjectSummary(secCert) as String? {
            self.certCommonName = name
        }

        // Try to get NotAfter (expiry) using SecCertificateCopyValues (available on iOS)
        var valuesRef: CFDictionary?
        let oids = [kSecOIDX509V1ValidityNotAfter] as CFArray
        let status = SecCertificateCopyValues(secCert, oids, &valuesRef)
        if status == errSecSuccess, let values = valuesRef as? [String: Any],
           let notAfterEntry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let expiry = notAfterEntry[kSecPropertyKeyValue as String] as? Date {
            self.certExpiry = expiry
        } else {
            // If SecCertificateCopyValues didn't return a Date (rare), leave nil.
            self.certExpiry = nil
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
