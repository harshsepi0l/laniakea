protocol SnapiArticleRepo {
    func fetchSnapiArticle(completion: @escaping (Result<[SnapiArticle], Error>) -> Void)
}
