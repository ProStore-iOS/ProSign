import SwiftUI

@main
struct ProSign: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            // ---- Signer Tab ----
            NavigationStack {
                SignerView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("ProSign - Signer")
                                .font(.headline)
                        }
                    }
            }
            .tabItem {
                Image(systemName: "hammer")
                Text("Signer")
            }

            // ---- Certificates Tab ----
            NavigationStack {
                CertificateView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("ProSign - Certificates")
                                .font(.headline)
                        }
                    }
            }
            .tabItem {
                Image(systemName: "key")
                Text("Certificates")
            }

            // ---- About Tab ----
            NavigationStack {
                AboutView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("ProSign - About")
                                .font(.headline)
                        }
                    }
            }
            .tabItem {
                Image(systemName: "info.circle")
                Text("About")
            }
        }
    }
}
