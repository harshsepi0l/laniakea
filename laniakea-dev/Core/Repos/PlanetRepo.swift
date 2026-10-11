protocol PlanetRepo {
    func loadPlanets() async throws -> [Planet]
}
