import Combine
import Foundation

class StoriesViewModel: ObservableObject {
    @Published private(set) var aiSummaries: [String: String] = [:]
    private var requested: Set<String> = []
    private let fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase

    init(fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase) {
        self.fetchGeneratedArticleUseCase = fetchGeneratedArticleUseCase
    }

    func summary(for listing: ArticleListing) -> String {
        aiSummaries[listing.generatedPath] ?? listing.summary
    }

    func loadSummary(for listing: ArticleListing) {
        let path = listing.generatedPath
        guard !requested.contains(path) else { return }
        requested.insert(path)
        fetchGeneratedArticleUseCase.execute(path: path) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let generated?) = result {
                    self?.aiSummaries[path] = generated.summary
                } else {
                    self?.requested.remove(path)
                }
            }
        }
    }
}
