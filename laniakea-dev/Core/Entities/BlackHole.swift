import Foundation
import simd

/// A black hole with a known position: the Milky Way's central one, stellar-mass black holes in
/// binary stars, and the supermassive ones at the hearts of galaxies with measured masses.
///
/// Black holes give off no light, so every value here comes from what they do to things around
/// them: stars orbiting them, gas swirling into them, or the X-rays that gas gives off.
struct BlackHole: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        /// Millions to billions of Suns, at a galaxy's centre.
        case supermassive
        /// A few to a few tens of Suns: what's left of a massive star.
        case stellar
    }

    /// How it was found, which says what kind of evidence there is for it.
    enum Setting: String, Codable {
        /// Sagittarius A*, the Milky Way's own.
        case galacticCentre
        /// The centre of another galaxy.
        case galaxyCentre
        /// Flares up in X-rays as it pulls gas off a companion star, then fades for years.
        case xRayTransient
        /// Shines steadily in X-rays, feeding off a massive companion's wind (Cygnus X-1).
        case xRayPersistent
        /// Silent: found only by the wobble of the star orbiting it (Gaia BH1, BH2, BH3).
        case dormantBinary
    }

    /// How a catalog qualifies a number.
    enum Limit: String, Codable {
        case none, approximate, atLeast, roughlyAtLeast, atMost

        /// For display, before the number.
        var symbol: String {
            switch self {
            case .none: return ""
            case .approximate: return "≈ "
            case .atLeast: return "≥ "
            case .roughlyAtLeast: return "≳ "
            case .atMost: return "≤ "
            }
        }

        /// The flags VizieR catalogs use (">", "<=", "~", ">~").
        init(flag: String?) {
            switch flag?.trimmingCharacters(in: .whitespaces) ?? "" {
            case ">", ">=": self = .atLeast
            case ">~", "~>": self = .roughlyAtLeast
            case "<", "<=": self = .atMost
            case "~": self = .approximate
            default: self = .none
            }
        }
    }

    /// One published mass, in Suns.
    struct Mass: Codable, Hashable {
        let suns: Double
        /// Errors, in Suns, above and below.
        var plus: Double?
        var minus: Double?
        /// The top of a range, when the source gives one (6.9–8.2) instead of an error.
        var rangeTop: Double?
        var limit: Limit = .none
        /// How it was measured, in plain words.
        let method: String
        /// Who measured it.
        let source: String
    }

    let id: String
    let name: String
    /// Other names it goes by, for search.
    var aliases: [String] = []
    let kind: Kind
    let setting: Setting
    /// J2000 position on the sky.
    let raDeg: Double
    let decDeg: Double
    /// Distance from the Sun, in parsecs; nil when no one has measured it.
    var distanceParsecs: Double?
    var distanceErrorParsecs: Double?
    var distanceLimit: Limit = .none
    /// How the distance was found.
    var distanceMethod: String?
    var masses: [Mass] = []
    /// The mass function from the companion star's orbit, in Suns: a strict minimum for the black
    /// hole's mass, whatever the orbit's tilt.
    var massFunction: Mass?
    /// Its mass has been weighed from a companion's orbit; otherwise it's a candidate, picked out by
    /// its X-ray behaviour alone.
    var isConfirmed = true
    var discoveryYear: Int?
    /// The companion star's spectral type, for binaries.
    var companionType: String?
    var orbitalPeriodDays: Double?
    /// Cosmicflows-4's PGC number for a supermassive black hole's galaxy.
    var hostPGC: Int?
    /// Where each value comes from, in the order shown.
    var sources: [String] = []
    /// What's estimated or uncertain, in plain sentences.
    var notes: [String] = []

    /// Galactic Cartesian position in parsecs (x toward the Galactic Centre, z toward Galactic
    /// north), like `StarSystem.position`; nil without a distance.
    var galacticPosition: SIMD3<Double>? {
        guard let d = distanceParsecs else { return nil }
        let g = SkyCoordinates.galactic(raDeg: raDeg, decDeg: decDeg)
        return SkyCoordinates.cartesian(longitudeDeg: g.l, latitudeDeg: g.b, distance: d)
    }

    /// The mass to size its dot by and quote first: the first published one, else the minimum
    /// from its orbit.
    var leadingMass: Mass? { masses.first ?? massFunction }
}
