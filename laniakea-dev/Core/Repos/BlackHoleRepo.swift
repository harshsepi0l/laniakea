protocol BlackHoleRepo {
    /// Black holes in the Milky Way with known positions: Sagittarius A* at its centre and
    /// stellar-mass black holes in binary stars. Those without a measured distance are left out
    /// of the map but kept here.
    func milkyWayBlackHoles() async throws -> [BlackHole]
    /// Supermassive black holes with measured masses, by the Cosmicflows-4 PGC number of their galaxy.
    func supermassiveBlackHoles() async throws -> [Int: BlackHole]
}
