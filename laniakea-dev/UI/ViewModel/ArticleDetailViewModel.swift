import Combine
import Foundation

class ArticleDetailViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case generated(GeneratedArticle)
        case notGenerated
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    let listing: ArticleListing
    private let fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase

    init(listing: ArticleListing, fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase) {
        self.listing = listing
        self.fetchGeneratedArticleUseCase = fetchGeneratedArticleUseCase
    }

    func load() {
        if case .generated = state { return }
        state = .loading
        fetchGeneratedArticleUseCase.execute(path: listing.generatedPath) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let generated?):
                    self?.state = .generated(generated)
                case .success(nil):
                    self?.state = .notGenerated
                case .failure(let error):
                    self?.state = .failed(error.localizedDescription)
                }
            }
        }
    }
}
