protocol CosmicRepo {
    /// Galaxy groups inside Laniakea, with its outline.
    func laniakea() async throws -> LaniakeaMap
    /// The galaxies with measured distances in a group.
    func galaxies(in group: GalaxyGroup) async throws -> [Galaxy]
    /// Stars in the Milky Way with confirmed planets.
    func starSystems() async throws -> [StarSystem]
    /// Stars bright enough to see with the eye, with distances, sizes and names where known.
    func nakedEyeStars() async throws -> [NakedEyeStar]
    func planets(of system: StarSystem) async throws -> [Exoplanet]

    // Fact sheets
    func details(of group: GalaxyGroup) async throws -> GroupDetails
    func details(of galaxy: Galaxy) async throws -> GalaxyDetails
    func details(of system: StarSystem) async throws -> StarDetails
    func sun() async throws -> SunDetails
    func constellations() async throws -> ConstellationBoundaries
    func galaxyColors() async throws -> GalaxyColors
}
