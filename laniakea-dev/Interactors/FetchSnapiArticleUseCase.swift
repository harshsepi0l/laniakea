class FetchSnapiArticleUseCase {
    private let repository: SnapiArticleRepo

    init(repository: SnapiArticleRepo) {
        self.repository = repository
    }

    func execute(completion: @escaping (Result<[SnapiArticle], Error>) -> Void) {
        repository.fetchSnapiArticle(completion: completion)
    }
}
