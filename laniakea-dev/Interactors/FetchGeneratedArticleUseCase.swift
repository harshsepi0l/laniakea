class FetchGeneratedArticleUseCase {
    private let repository: GeneratedArticleRepo

    init(repository: GeneratedArticleRepo) {
        self.repository = repository
    }

    func execute(path: String, completion: @escaping (Result<GeneratedArticle?, Error>) -> Void) {
        repository.fetchGeneratedArticle(path: path, completion: completion)
    }
}
