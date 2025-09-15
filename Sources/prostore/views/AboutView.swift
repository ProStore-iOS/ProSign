import SwiftUI

struct Credit: Identifiable {
    var id = UUID()
    var name: String
    var role: String
    var profileURL: URL
    var avatarURL: URL
}

struct AboutView: View {
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

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                VStack(spacing: 12) {
                    if let url = appIconURL {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(Color.blue.opacity(0.1)) // Subtle background
                                    )
                                    .padding(4)
                            } else if phase.error != nil {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.blue.opacity(0.6)) // Tinted fallback
                            } else {
                                ProgressView()
                                    .tint(.blue) // Tinted spinner
                                    .frame(width: 80, height: 80)
                            }
                        }
                        .animation(.easeIn(duration: 0.3), value: url) // Fade-in animation
                    }

                    Text("ProStore")
                        .font(.title2)
                        .fontWeight(.bold) // Bolder for emphasis
                        .foregroundColor(.primary)

                    Text("Version \(versionString)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24) // More spacing
                .listRowInsets(EdgeInsets())
                .background(Color.blue.opacity(0.05)) // Subtle list row background

                Section(header: Text("Credits")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)) {
                    ForEach(credits) { c in
                        CreditRow(credit: c)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(UIColor.systemBackground)) // Clean background
            .navigationTitle("About ProStore")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.blue) // Consistent blue accent
        }
    }
}

struct CreditRow: View {
    let credit: Credit
    @Environment(\.openURL) var openURL
    @State private var isTapped = false // For button animation

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: credit.avatarURL) { phase in
                if let img = phase.image {
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1) // Modern border
                        )
                } else if phase.error != nil {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.blue.opacity(0.6)) // Tinted fallback
                } else {
                    ProgressView()
                        .tint(.blue) // Tinted spinner
                        .frame(width: 48, height: 48)
                }
            }
            .animation(.easeIn(duration: 0.3), value: credit.avatarURL) // Fade-in animation

            VStack(alignment: .leading, spacing: 4) {
                Text(credit.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(credit.role)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                isTapped = true
                openURL(credit.profileURL)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isTapped = false
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.large)
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1)) // Subtle button background
                    .clipShape(Circle())
                    .scaleEffect(isTapped ? 0.9 : 1.0) // Tap animation
            }
            .buttonStyle(BorderlessButtonStyle())
            .animation(.easeInOut(duration: 0.2), value: isTapped) // Smooth tap animation
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05)) // Subtle row background
        )
        .padding(.horizontal, 4)
    }
}