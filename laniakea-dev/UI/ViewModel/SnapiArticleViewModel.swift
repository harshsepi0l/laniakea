import Combine
import SwiftUI

class SnapiArticleViewModel: ObservableObject {
    @Published var snapiArticle: [SnapiArticle] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    private let fetchSnapiArticleUseCase: FetchSnapiArticleUseCase
    private var lastFetchDate: Date?
    private let cacheInterval: TimeInterval = 1800

    init(fetchSnapiArticleUseCase: FetchSnapiArticleUseCase) {
        self.fetchSnapiArticleUseCase = fetchSnapiArticleUseCase
    }

    func loadSnapiArticle() {
        if isLoading { return }
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheInterval {
            return
        }

        isLoading = true
        errorMessage = nil
        fetchSnapiArticleUseCase.execute { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let articles):
                    self.snapiArticle = articles
                    self.lastFetchDate = Date()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
