import Foundation

/// Moons, dwarf planets and the Moon in the sky, all from JPL Horizons (`HorizonsMoonsService`).
extension CosmicCatalog: SolarSystemBodiesRepo {
    private static let moons = HorizonsMoonsService()

    /// Orbits are osculating elements for today; a week's drift is far below a pixel for bodies this
    /// far out.
    func dwarfPlanets() async throws -> [DwarfPlanet] {
        try await cached(DiskCache<[DwarfPlanet]>(name: "horizons-dwarf-planets-v1"), maxAge: 7 * 86400) {
            try await Self.moons.dwarfPlanets()
        }
    }

    func moonListings() async throws -> [String: [MoonListing]] {
        let all = try await cached(DiskCache<[MoonListing]>(name: "horizons-moon-list-v1"), maxAge: 30 * 86400) {
            try await Self.moons.moonListings()
        }
        return Dictionary(grouping: all, by: \.primaryID)
    }

    /// A moon's osculating orbit drifts quickly (the Sun pulls hard on ours), so it's refreshed daily.
    func moon(id: String) async throws -> Moon {
        try await cached(DiskCache<Moon>(name: "horizons-moon-v1-\(id)"), maxAge: 86400) {
            try await Self.moons.moon(id: id)
        }
    }

    /// Fetched for two days and refreshed after six hours, so the span always covers the next day.
    func moonEphemeris() async throws -> MoonEphemeris {
        let cache = DiskCache<MoonEphemeris>(name: "horizons-moon-sky-v1")
        let soon = OrbitalElements.julianDay(Date().addingTimeInterval(24 * 3600))
        if let fresh = cache.load(maxAge: 6 * 3600), (fresh.samples.last?.julianDayTDB ?? 0) > soon { return fresh }
        do {
            let ephemeris = try await Self.moons.moonEphemeris()
            cache.save(ephemeris)
            return ephemeris
        } catch {
            // An old ephemeris still helps if it covers now.
            if let stale = cache.load(), stale.geocentric(at: Date()) != nil { return stale }
            throw error
        }
    }
}
