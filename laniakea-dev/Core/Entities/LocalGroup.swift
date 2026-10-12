import Foundation
import simd

/// The Local Group: the Milky Way, Andromeda, Triangulum and the dwarf galaxies bound to them, from
/// the Local Volume Database (Pace 2025, OJAp 8, 142).
///
/// Cosmicflows-4 only covers galaxies it measured itself: it splits the Local Group into the Milky
/// Way's group (1PGC 5064336, with just Leo I and Leo II) and Andromeda's (1PGC 2557), and lists the
/// Magellanic Clouds without any group. The Local Volume Database is current and complete for the
/// Local Group's known dwarfs, with one consistent set of distances, so the Local Group is built from it.
struct LocalGroup: Codable {
    /// Every confirmed member, the Milky Way first.
    let members: [LocalGroupGalaxy]
    /// The Local Group's centre (between the Milky Way and Andromeda, where the database measures
    /// `distance_lg` from), in supergalactic Cartesian kpc from the Sun.
    let centre: SIMD3<Double>
    /// Objects the database lists here that aren't yet confirmed as galaxies (they may be star
    /// clusters), left out.
    let candidateCount: Int

    /// The radius of the Local Group's zero-velocity surface, inside which galaxies have stopped
    /// moving apart with the universe: 1.18 ± 0.15 Mpc for an age of 14 Gyr (van den Bergh 1999, ApJ
    /// 517, L97). Field dwarfs inside it are counted as members.
    static let zeroVelocityRadiusKpc = 1180.0

    /// Whether a Cosmicflows-4 group is one of the Local Group's pieces: the two halves it names, or a
    /// group inside the Local Group's edge that matches a member on the sky (within 5°) and in distance
    /// (within 30%). Matching keeps a galaxy whose distances disagree in the two catalogs on one map
    /// only: Cosmicflows-4 puts Sagittarius dIrr inside the edge, the Local Volume Database outside.
    func includes(_ group: GalaxyGroup) -> Bool {
        if group.id == GalaxyGroup.andromedaGroupID || group.id == GalaxyGroup.milkyWayGroupID { return true }
        let p = group.position * 1000
        guard simd_distance(p, centre) <= Self.zeroVelocityRadiusKpc else { return false }
        return members.contains { m in
            guard let d = m.distanceKpc else { return false }
            return abs(d - simd_length(p)) < 0.3 * d && SkyCoordinates.separation(m.position, p) < 5
        }
    }

    var milkyWay: LocalGroupGalaxy? { members.first { $0.id == LocalGroupGalaxy.milkyWayID } }
    var andromeda: LocalGroupGalaxy? { members.first { $0.id == LocalGroupGalaxy.andromedaID } }
}

/// A galaxy in the Local Group.
struct LocalGroupGalaxy: Codable, Identifiable, Hashable {
    /// The database's keys for the two big galaxies.
    static let milkyWayID = "mw"
    static let andromedaID = "m_031"

    /// The database's key, such as "leo_1".
    let id: String
    let name: String
    /// Which big galaxy's family it's in, following its hosts up (the SMC orbits the LMC, which
    /// orbits the Milky Way).
    let side: Side
    /// The galaxy it orbits directly, by key and name; nil for the big two and free-floating dwarfs.
    let hostID: String?
    let hostName: String?
    /// From the Sun, kpc; nil for the Milky Way.
    let distanceKpc: Double?
    /// Half the spread of the published uncertainty, kpc, where given.
    let distanceErrorKpc: Double?
    /// From its host's centre, kpc.
    let distanceFromHostKpc: Double?
    /// From the Local Group's centre, kpc.
    let distanceFromCentreKpc: Double?
    /// Supergalactic Cartesian kpc from the Sun. The Milky Way's is its centre, Sagittarius A*.
    let position: SIMD3<Double>
    let raDeg: Double
    let decDeg: Double
    /// Hubble type from McConnachie (2012), such as "dSph"; nil for dwarfs found since.
    let morphology: String?
    let absoluteMagnitudeV: Double?
    /// log10 of the stellar mass in Suns.
    let logStellarMass: Double?
    /// Measured velocity along our line of sight, as seen from the Sun, km/s; positive is away.
    let velocityKmS: Double?
    /// Half-light radius on the sky, arcminutes.
    let halfLightArcmin: Double?
    /// The paper its distance comes from, as "Savino et al. 2022".
    let distanceSource: String?

    enum Side: String, Codable {
        case milkyWay, andromeda, neither
    }

    /// Its host's name as used in a sentence: "the Milky Way", "the Large Magellanic Cloud", "the Andromeda Galaxy".
    var hostInSentence: String? {
        hostName.map { $0 == "Milky Way" || $0.hasSuffix("Cloud") || $0.hasSuffix("Galaxy") ? "the \($0)" : $0 }
    }

    /// Light in the V band relative to the Sun (M_V = 4.83).
    var luminositySuns: Double? { absoluteMagnitudeV.map { pow(10, -0.4 * ($0 - 4.83)) } }
}
