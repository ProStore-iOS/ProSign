import SwiftUI

@main
struct ProStore: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SignerView()
            }
            .tabItem {
                Image(systemName: "hammer")
                Text("Signer")
            }

            NavigationStack {
                CertificateView()
            }
            .tabItem {
                Image(systemName: "key")
                Text("Certificates")
            }

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Image(systemName: "info.circle")
                Text("About")
            }
        }
    }
}