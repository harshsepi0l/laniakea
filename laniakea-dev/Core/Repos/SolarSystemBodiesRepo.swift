/// The Solar System beyond the eight planets: moons, dwarf planets and the Moon's sky position.
protocol SolarSystemBodiesRepo {
    /// The IAU's five dwarf planets.
    func dwarfPlanets() async throws -> [DwarfPlanet]
    /// Every named moon Horizons lists, grouped by the Horizons ID of the body it orbits.
    func moonListings() async throws -> [String: [MoonListing]]
    /// One moon's orbit and physical data.
    func moon(id: String) async throws -> Moon
    /// The Moon's geocentric position, hourly, covering at least the next day.
    func moonEphemeris() async throws -> MoonEphemeris
}
