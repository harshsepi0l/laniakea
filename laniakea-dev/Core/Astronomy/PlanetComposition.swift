import Foundation

/// Whether a planet is solid rock and metal or wrapped in gas, water or ice, and the color Atlas
/// draws it with: rocky planets brown, gas- and ice-rich planets blue.
enum PlanetComposition: String, Codable {
    case rocky, gasRich

    /// Solar System planets, from their measured density: the rocky planets are 3.9–5.5 g/cm³ and
    /// the giants, mostly hydrogen, helium and ices, are 0.7–1.7.
    static func solarSystem(densityGramsPerCm3: Double?) -> PlanetComposition? {
        densityGramsPerCm3.map { $0 >= rockyDensityLimit ? .rocky : .gasRich }
    }

    /// Planets of other stars, from the best evidence available:
    /// 1. Measured radius and mass: rocky if the planet is no larger than a ball of pure rock of that
    ///    mass, R ≤ 1.07 · M^(1/3.7) (Zeng et al. 2016, ApJ 819, 127). A fixed density cutoff fails
    ///    here because big rocky planets are compressed: K2-18 b is 3.7 g/cm³ yet a sub-Neptune. A
    ///    minimum mass (from radial velocities) can only prove a planet rocky. Masses the archive
    ///    estimated from size are skipped, since they'd only repeat the size.
    /// 2. Measured radius: almost all planets wider than 1.6 Earth radii hold thick envelopes of
    ///    hydrogen and helium (Rogers 2015, ApJ 801, 41).
    /// 3. Mass alone: worlds under 2 Earth masses are rocky (Chen & Kipping 2017, ApJ 834, 17).
    /// Radii the archive calculated from mass are skipped too; they'd only repeat the mass.
    static func exoplanet(radiusEarths: Double?, radiusIsEstimate: Bool, massEarths: Double?, massIsMinimum: Bool,
                          massIsEstimate: Bool) -> (composition: PlanetComposition, evidence: Evidence)? {
        let radius = radiusIsEstimate ? nil : radiusEarths
        let mass = massIsEstimate ? nil : massEarths
        // The archive's combined table can pair a radius and a mass from different papers; a density
        // beyond anything physical (Kepler-37 e would be 881 g/cm³) means they don't belong together.
        if let r = radius, let m = mass, r > 0, m > 0, earthDensity * m / (r * r * r) <= maxPlausibleDensity {
            if r <= pureRockRadius(massEarths: m) { return (.rocky, .size(forMass: true)) }
            if !massIsMinimum { return (.gasRich, .size(forMass: true)) }
        }
        if let r = radius { return (r < rockyRadiusLimit ? .rocky : .gasRich, .size(forMass: false)) }
        if let m = mass { return (m < rockyMassLimit ? .rocky : .gasRich, .mass(minimum: massIsMinimum)) }
        return nil
    }

    /// What decided a planet's makeup, matching the steps in `exoplanet`.
    enum Evidence {
        /// Radius compared with pure rock of its mass (true), or with 1.6 Earth radii (false).
        case size(forMass: Bool)
        case mass(minimum: Bool)

        func explanation(for composition: PlanetComposition) -> String {
            let rocky = composition == .rocky
            switch self {
            case .size(true): return rocky ? "compact enough for its mass to be solid rock" : "too large for its mass to be solid rock"
            case .size(false): return rocky ? "smaller than 1.6 × Earth" : "wider than 1.6 × Earth"
            case .mass(let minimum):
                if rocky { return minimum ? "under 2 × Earth's mass, if its orbit isn't tilted much" : "under 2 × Earth's mass" }
                return "over 2 × Earth's mass"
            }
        }
    }

    /// Radius in Earth radii of a planet made only of rock (no iron core), from Zeng et al. 2016.
    static func pureRockRadius(massEarths m: Double) -> Double { 1.07 * pow(m, 1 / 3.7) }

    static let rockyDensityLimit = 3.0
    /// g/cm³; the densest known planets are around 15–20.
    static let maxPlausibleDensity = 30.0
    static let rockyRadiusLimit = 1.6
    static let rockyMassLimit = 2.0
    /// g/cm³
    static let earthDensity = 5.51

    var name: String { self == .rocky ? "Rocky" : "Gas or ice-rich" }

    /// Brown for rock, a gassy blue for hydrogen and helium; the light-mode shades are deeper so they
    /// read on white.
    func color(dark: Bool) -> StarColor.RGB {
        switch (self, dark) {
        case (.rocky, true): return StarColor.RGB(r: 0.78, g: 0.56, b: 0.38)
        case (.rocky, false): return StarColor.RGB(r: 0.55, g: 0.36, b: 0.22)
        case (.gasRich, true): return StarColor.RGB(r: 0.52, g: 0.72, b: 0.98)
        case (.gasRich, false): return StarColor.RGB(r: 0.22, g: 0.44, b: 0.80)
        }
    }
}

extension Planet {
    var composition: PlanetComposition? { .solarSystem(densityGramsPerCm3: densityGramsPerCm3) }
}

extension Exoplanet {
    var makeup: (composition: PlanetComposition, evidence: PlanetComposition.Evidence)? {
        PlanetComposition.exoplanet(radiusEarths: radiusEarths, radiusIsEstimate: radiusIsEstimate ?? false,
                   massEarths: massEarths, massIsMinimum: massIsMinimum ?? false, massIsEstimate: massIsEstimate ?? false)
    }

    var composition: PlanetComposition? { makeup?.composition }

    /// Density from a measured radius and a measured true mass, in g/cm³; nil when either is an
    /// estimate or a minimum, or the two don't fit together.
    var densityGramsPerCm3: Double? {
        guard let r = radiusEarths, radiusIsEstimate != true, massIsEstimate != true, massIsMinimum != true,
              let m = massEarths, r > 0
        else { return nil }
        let density = PlanetComposition.earthDensity * m / (r * r * r)
        return density <= PlanetComposition.maxPlausibleDensity ? density : nil
    }
}
