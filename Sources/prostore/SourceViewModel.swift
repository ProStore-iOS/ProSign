import Foundation
import Combine
import ProSourceManager

@MainActor
final class SourceViewModel: ObservableObject {
    @Published var outputs: [(URL, Result<String, Error>)] = []
    @Published var isLoading: Bool = false

    func load(urls: [URL]) async {
        isLoading = true
        let results = await ProSourceManager.fetchJSONStrings(from: urls)
        self.outputs = results
        isLoading = false
    }
}