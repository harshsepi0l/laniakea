protocol GeneratedArticleRepo {
    /// Succeeds with nil when no AI version has been generated for this article yet.
    func fetchGeneratedArticle(path: String, completion: @escaping (Result<GeneratedArticle?, Error>) -> Void)
}
