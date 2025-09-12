import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SourceViewModel()

    // Replace these with your real source URLs
    private let urls: [URL] = [
        URL(string: "https://repository.apptesters.org")!,
        URL(string: "https://quarksources.github.io/altstore-complete.json")!
    ]

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading && vm.outputs.isEmpty {
                    VStack {
                        ProgressView()
                        Text("Fetching sources...")
                            .font(.caption)
                    }
                } else {
                    List {
                        ForEach(vm.outputs, id: \.0) { item in
                            Section(header: Text(item.0.absoluteString).font(.caption)) {
                                switch item.1 {
                                case .success(let prettyJSON):
                                    // Show JSON in a scrollable monospace block
                                    ScrollView(.horizontal) {
                                        Text(prettyJSON)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(.vertical, 6)
                                    }
                                    .frame(maxHeight: 300)
                                case .failure(let err):
                                    Text("Error: \(err.localizedDescription)")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                Button("Reload") {
                    Task {
                        await vm.load(urls: urls)
                    }
                }
            }
            .task {
                // Load automatically when view appears
                await vm.load(urls: urls)
            }
        }
    }
}