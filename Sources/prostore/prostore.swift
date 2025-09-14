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