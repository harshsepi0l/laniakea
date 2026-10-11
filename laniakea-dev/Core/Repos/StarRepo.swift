protocol StarRepo {
    func loadStars() async throws -> [Star]
}
