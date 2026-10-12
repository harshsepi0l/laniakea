import Foundation

/// A natural satellite as JPL Horizons describes it: its orbit around its planet and the physical
/// data sheet Horizons keeps for it. Values are optional because the sheets differ from moon to moon.
struct Moon: Codable, Identifiable, Equatable {
    /// Horizons body ID, e.g. "501" for Io or "120136199" for Dysnomia.
    let id: String
    let name: String
    /// Horizons ID of the body it orbits, e.g. "599".
    let primaryID: String
    /// Osculating elements around the primary (J2000 ecliptic, au and days) on the day they were fetched.
    let orbit: OrbitalElements
    /// Volume-equivalent radius; for an irregular moon, the cube root of its three semi-axes' product.
    let meanRadiusKm: Double?
    /// The three semi-axes when Horizons gives the shape, e.g. Phobos's 13.1 × 11.1 × 9.3 km.
    let triaxialRadiiKm: [Double]?
    /// From GM when Horizons gives it (mass = GM / G), else Horizons' mass.
    let massKg: Double?
    let densityGramsPerCm3: Double?
    let geometricAlbedo: Double?
    /// Horizons lists the rotation as synchronous: it keeps one face toward its planet.
    let isSynchronous: Bool

    static let kmPerAU = 149_597_870.7
}

/// A moon named in Horizons' list of major bodies (COMMAND='MB'), before its own data is loaded.
struct MoonListing: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let primaryID: String
}

/// A dwarf planet. Its orbit and most facts come from Horizons like a planet's; `notes` say where
/// a value came from when Horizons' own sheet for the body doesn't have it.
struct DwarfPlanet: Codable, Identifiable, Equatable {
    let planet: Planet
    /// Minor-planet number and provisional designation, e.g. "136199 · 2003 UB313".
    let designation: String?
    /// Semi-axes when the body is measured as an ellipsoid (Haumea).
    let triaxialRadiiKm: [Double]?
    /// The mass is the middle of a range Horizons gives (Eris).
    let massIsEstimate: Bool
    let geometricAlbedo: Double?
    let absoluteMagnitude: Double?
    /// Where values came from, in plain words.
    let notes: [String]

    var id: String { planet.id }
}

/// The IAU's five dwarf planets (IAU Resolution B5, 2006, and the 2008 naming of Makemake and
/// Haumea). Horizons has no physical sheet for Makemake, so its size comes from the literature.
enum DwarfPlanets {
    struct Body {
        let id: String
        let name: String
        /// Horizons COMMAND for the orbit: "999" for Pluto (a major body), "136199;" style for small
        /// bodies (the `DES=` form fails).
        let orbitCommand: String
        /// Horizons record with the physical sheet when the orbit's record lacks it: the primary
        /// body of Horizons' TNO-satellite solution.
        let physicalCommand: String?
    }

    static let all: [Body] = [
        Body(id: "2000001", name: "Ceres", orbitCommand: "1;", physicalCommand: nil),
        Body(id: "999", name: "Pluto", orbitCommand: "999", physicalCommand: nil),
        Body(id: "2136108", name: "Haumea", orbitCommand: "136108;", physicalCommand: "920136108"),
        Body(id: "2136472", name: "Makemake", orbitCommand: "136472;", physicalCommand: nil),
        Body(id: "2136199", name: "Eris", orbitCommand: "136199;", physicalCommand: "920136199"),
    ]

    /// Makemake's size from stellar occultations and thermal data: 1434 × 1422 km
    /// (Brown 2013, ApJL 767, L7), a volume-equivalent radius of about 715 km. Its mass is unmeasured.
    static let makemakeRadiiKm: [Double] = [717, 717, 711]

    static func isDwarf(_ planetID: String) -> Bool { all.contains { $0.id == planetID } }

    /// Horizons record that moons of this dwarf planet orbit (the primary body, not the barycenter).
    static func moonCentre(of planetID: String) -> String? {
        switch planetID {
        case "999": return "999"
        case "2136199": return "920136199"
        case "2136108": return "920136108"
        default: return nil
        }
    }
}

extension Moon {
    /// The body a Horizons moon ID orbits: "501" → "599"; "120136199" → Eris.
    static func primaryID(ofMoon id: String) -> String? {
        if id.count == 3, let n = Int(id), n % 100 != 99 { return "\(n / 100)99" }
        if id.count == 9, id.first != "9" {
            let number = String(id.dropFirst(3))
            return DwarfPlanets.all.first { $0.orbitCommand == "\(Int(number) ?? -1);" }?.id
        }
        return nil
    }

    /// Distance from its primary at a date, in km.
    func distanceKm(at date: Date) -> Double {
        let p = orbit.position(at: date)
        return (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot() * Self.kmPerAU
    }
}
