import Foundation
import simd

/// A group or cluster of galaxies from Cosmicflows-4 (Tully et al. 2023), identified by the PGC
/// number of its brightest galaxy.
struct GalaxyGroup: Codable, Identifiable, Hashable {
    /// Andromeda's group (PGC 2557): Andromeda, Triangulum and their satellites, the Local Group's
    /// other half. Cosmicflows-4 has no entry for the Milky Way or its satellites, so this is the
    /// only part of our own Local Group it lists.
    static let localGroupID = 2557

    let id: Int
    let name: String
    let galaxyCount: Int
    let distanceMpc: Double
    /// Supergalactic Cartesian position in Mpc, with the Milky Way at the origin.
    let position: SIMD3<Double>
    /// In a boundary-map cell next to Laniakea rather than inside it. The map's cells are about
    /// 10 Mpc wide, so membership this close to the edge is uncertain (the Hydra Cluster is one).
    let isOnBoundary: Bool
    /// Matched to a galaxy cluster in SIMBAD, rather than a group or a lone galaxy.
    let isCluster: Bool
    /// The color of its leading (brightest) galaxy.
    let color: GalaxyColor?
    /// Measured velocity along our line of sight, as seen from the Sun, km/s; positive is away.
    /// It includes the expansion of the universe.
    var velocityKmS: Double?
}

/// The broad Hubble types.
enum GalaxyType: String, Codable, CaseIterable {
    case spiral, lenticular, elliptical, irregular, dwarfSpheroidal

    /// From a Hubble classification such as "SAB(rs)bc" (spiral) or "E-E/S0" (elliptical), as SIMBAD gives it.
    init?(morphology: String?) {
        guard var t = morphology?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.hasPrefix("dSph") { self = .dwarfSpheroidal; return }
        if t.hasPrefix("cD") { self = .elliptical; return }
        // Drop size prefixes such as "d" (dwarf) in "dE" or "dIrr".
        while let first = t.first, first.isLowercase { t.removeFirst() }
        if t.hasPrefix("E") { self = .elliptical }
        else if t.range(of: #"^S(AB|A|B)?0"#, options: .regularExpression) != nil { self = .lenticular }
        // Magellanic spirals (Sm) go with the irregulars, as RC3's stage 9 does.
        else if t.range(of: #"^S(AB|A|B)?(\([^)]*\))?m"#, options: .regularExpression) != nil { self = .irregular }
        else if t.hasPrefix("S") { self = .spiral }
        else if t.hasPrefix("I") { self = .irregular }
        else { return nil }
    }

    /// From RC3's numeric stage T: −6…−4 ellipticals, −3…0 lenticulars (with S0/a, as SIMBAD's "S0/a"
    /// types are classed above), 1…8 spirals (Sa to Sdm), 9, 10 and 90 Magellanic and irregular.
    init?(rc3Stage t: Double) {
        switch t {
        case ...(-3.5): self = .elliptical
        case ..<0.5: self = .lenticular
        case ...8.5: self = .spiral
        case ...10.5, 90: self = .irregular
        default: return nil
        }
    }
}

/// A galaxy's color: the combined light of its stars, as the B−V index used for single stars.
struct GalaxyColor: Codable, Hashable {
    /// Corrected for dust in the Milky Way and inside the galaxy.
    let bMinusV: Double
    /// Measured for this galaxy, or else typical of galaxies of its type.
    let isMeasured: Bool
    var typeName: String?
}

/// Galaxy colors from the Third Reference Catalogue of Bright Galaxies (RC3, de Vaucouleurs et al. 1991).
struct GalaxyColors: Codable {
    /// Measured B−V by PGC number.
    let measured: [Int: Double]
    /// RC3 Hubble type by PGC number.
    let types: [Int: GalaxyType]
    /// The median measured B−V of each type.
    let typical: [GalaxyType: Double]

    /// Measured when RC3 has it, else typical of its type (from SIMBAD's classification, then RC3's).
    func color(pgc: Int, morphology: String? = nil) -> GalaxyColor? {
        if let bv = measured[pgc] { return GalaxyColor(bMinusV: bv, isMeasured: true) }
        guard let type = GalaxyType(morphology: morphology) ?? types[pgc], let bv = typical[type] else { return nil }
        return GalaxyColor(bMinusV: bv, isMeasured: false, typeName: type.rawValue)
    }
}

/// A galaxy from Cosmicflows-4 with a measured distance.
struct Galaxy: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let groupID: Int
    let distanceMpc: Double
    /// Distance uncertainty in Mpc, from the distance-modulus error.
    let distanceErrorMpc: Double?
    let position: SIMD3<Double>
    /// Hubble type from SIMBAD, such as "SA(s)b".
    let morphology: String?
    let color: GalaxyColor?
}

/// Laniakea as Dupuy & Courtois (2023) drew it from Cosmicflows-4: the groups inside its basin of
/// attraction, plus the basin's cells for drawing its outline.
struct LaniakeaMap: Codable {
    let groups: [GalaxyGroup]
    /// Supergalactic (x, y) centres in Mpc of the basin's cells seen from above, deduplicated.
    let outlineCells: [SIMD2<Double>]
    let cellSizeMpc: Double
    let volumeMpc3: Double
    /// The widest distance across Laniakea, in Mpc.
    let longestSpanMpc: Double
    /// The average position of Laniakea's cells, in supergalactic Mpc.
    let centre: SIMD3<Double>
    /// Typical of a spiral like ours: the Milky Way's own color can't be measured from inside it.
    let milkyWayColor: GalaxyColor?
    /// Every one of the basin's cells in supergalactic Mpc, for its true 3D shape.
    var cells: [SIMD3<Double>]?
}

/// A way of measuring a galaxy's distance, as used by Cosmicflows-4.
enum DistanceMethod: String, Codable, CaseIterable {
    case cepheids, redGiants, masers, calibrators, supernovaIa, supernovaII, surfaceBrightness, tullyFisher, fundamentalPlane

    var name: String {
        switch self {
        case .cepheids: return "Cepheid variable stars"
        case .redGiants: return "Brightest red giants"
        case .masers: return "Water masers"
        case .calibrators: return "Cepheids, red giants or masers"
        case .supernovaIa: return "Type Ia supernovae"
        case .supernovaII: return "Type II supernovae"
        case .surfaceBrightness: return "Surface brightness fluctuations"
        case .tullyFisher: return "Spiral rotation speed (Tully–Fisher)"
        case .fundamentalPlane: return "Elliptical star motions (fundamental plane)"
        }
    }
}

/// Facts about a galaxy group from Cosmicflows-4, loaded for its fact sheet.
struct GroupDetails: Codable {
    let distanceErrorMpc: Double?
    /// Velocity along our line of sight, as seen from the Sun, km/s; positive is away.
    let velocityKmS: Double?
    /// Motion on top of the universe's expansion, measured against the cosmic microwave background,
    /// km/s; positive is outward.
    let peculiarVelocityKmS: Double?
    let peculiarVelocityErrorKmS: Double?
    /// How many of the group's galaxies each method measured.
    let methods: [MethodCount]

    struct MethodCount: Codable {
        let method: DistanceMethod
        /// Nil when the catalog doesn't count them.
        let galaxies: Int?
    }
}

/// Facts about a galaxy from SIMBAD and Cosmicflows-4, loaded for its fact sheet.
struct GalaxyDetails: Codable {
    /// Hubble type, such as "SA(s)b".
    let morphology: String?
    /// Apparent size along the long axis, in arcminutes.
    let majorAxisArcmin: Double?
    var minorAxisArcmin: Double?
    /// Direction of the long axis on the sky, degrees from north toward east.
    var positionAngleDeg: Double?
    /// Velocity along our line of sight, as seen from the Sun, km/s; positive is away.
    let velocityKmS: Double?
    let methods: [DistanceMethod]
}

/// A planet host star's properties from the NASA Exoplanet Archive.
struct StarDetails: Codable {
    let spectralType: String?
    let temperatureK: Double?
    let radiusSuns: Double?
    let massSuns: Double?
    let ageGyr: Double?
    /// log10 of luminosity in Suns.
    let logLuminositySuns: Double?
    /// [Fe/H] in dex.
    let metallicity: Double?
    let apparentMagnitude: Double?
    let starCount: Int?
}

/// The Sun's data sheet from JPL Horizons.
struct SunDetails: Codable {
    let radiusKm: Double?
    let massKg: Double?
    let densityGramsPerCm3: Double?
    let surfaceGravity: Double?
    let escapeSpeedKmS: Double?
    let effectiveTemperatureK: Double?
    let luminosityWatts: Double?
    let rotationDays: Double?
    let axialTiltDeg: Double?
    /// Speed relative to the stars around it, km/s.
    let speedNearbyStarsKmS: Double?
    /// Speed relative to the cosmic microwave background, km/s.
    let speedCosmicBackgroundKmS: Double?
}

/// A star bright enough to see with the eye (magnitude 6 or brighter), from the Yale Bright Star
/// Catalogue, with its Hipparcos distance, measured size (JSDC) and measured temperature (PASTEL)
/// where they exist.
struct NakedEyeStar: Codable, Identifiable, Hashable {
    /// Bright Star Catalogue (HR) number.
    let id: Int
    /// The IAU's official name, such as "Pollux".
    let properName: String?
    /// Traditional designation, such as "β Geminorum".
    let designation: String?
    let hd: Int?
    let raDeg: Double
    let decDeg: Double
    let magnitude: Double
    let bMinusV: Double?
    let spectralType: String?
    /// Hipparcos new reduction (van Leeuwen 2007), in milliarcseconds.
    let parallaxMas: Double?
    let parallaxErrorMas: Double?
    /// Limb-darkened angular diameter from the JMMC Stellar Diameters Catalogue, in milliarcseconds.
    let angularDiameterMas: Double?
    /// Median of published measurements (PASTEL); nil when none exist.
    let measuredTemperatureK: Double?
    /// Proper motion (Hipparcos new reduction, else the Bright Star Catalogue): μα cos δ and μδ, mas/yr.
    var pmRAMasPerYear: Double?
    var pmDecMasPerYear: Double?
    /// Bright Star Catalogue radial velocity, km/s; positive is away.
    var radialVelocityKmS: Double?

    var name: String { properName ?? designation ?? "HR \(id)" }

    /// Distance from a parallax measured to better than 20%; nil otherwise.
    var distanceParsecs: Double? {
        guard let p = parallaxMas, let e = parallaxErrorMas, p > 0, e < 0.2 * p else { return nil }
        return 1000 / p
    }

    var distanceErrorParsecs: Double? {
        guard let d = distanceParsecs, let p = parallaxMas, let e = parallaxErrorMas else { return nil }
        return d * e / p
    }

    /// Measured, else estimated from its color (Ballesteros 2012), which runs low for giants.
    var temperatureK: Double? { measuredTemperatureK ?? bMinusV.map { StarColor.temperature(bv: $0) } }

    /// Radius in solar radii: half the angular diameter times the distance (1 AU = 215.03 R☉).
    var radiusSuns: Double? {
        guard let theta = angularDiameterMas, let d = distanceParsecs else { return nil }
        return theta / 2 / 1000 * d * 215.03
    }

    /// Luminosity in visible (V-band) light relative to the Sun (M_V = 4.83), ignoring dust.
    var visualLuminositySuns: Double? {
        guard let d = distanceParsecs else { return nil }
        let absolute = magnitude - 5 * log10(d / 10)
        return pow(10, -0.4 * (absolute - 4.83))
    }

    /// Galactic Cartesian position in parsecs, like `StarSystem.position`.
    var position: SIMD3<Double>? {
        guard let d = distanceParsecs else { return nil }
        let g = SkyCoordinates.galactic(raDeg: raDeg, decDeg: decDeg)
        return SkyCoordinates.cartesian(longitudeDeg: g.l, latitudeDeg: g.b, distance: d)
    }
}

/// A star with at least one confirmed planet, from the NASA Exoplanet Archive.
struct StarSystem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let distanceParsecs: Double
    /// Confirmed planets orbiting this star (not counting other stars in the same system).
    let planetCount: Int
    let spectralType: String?
    let temperatureK: Double?
    /// HD catalog number, which links it to the naked-eye stars.
    var hd: Int?
    /// Galactic Cartesian position in parsecs, x toward the Galactic Centre, z toward Galactic north.
    let position: SIMD3<Double>
    /// Proper motion, μα cos δ and μδ in mas/yr, and radial velocity in km/s (Exoplanet Archive).
    var pmRAMasPerYear: Double?
    var pmDecMasPerYear: Double?
    var radialVelocityKmS: Double?
}

/// A planet orbiting another star, from the NASA Exoplanet Archive.
struct Exoplanet: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let semiMajorAxisAU: Double?
    let periodDays: Double?
    let eccentricity: Double?
    let radiusEarths: Double?
    /// The archive calculated the radius from the planet's mass rather than measuring it.
    let radiusIsEstimate: Bool?
    let massEarths: Double?
    /// The mass is a minimum (M sin i, from radial velocities) because the orbit's tilt is unknown.
    var massIsMinimum: Bool?
    /// The archive estimated the mass from the planet's size rather than measuring it.
    var massIsEstimate: Bool?
    /// Julian date when the planet passes between its star and Earth: a transit, or for planets found
    /// by radial velocity, the published time of conjunction.
    let transitMidpointJD: Double?
    /// Temperature it would have from its star's heat alone, in kelvin.
    let equilibriumTempK: Double?
    /// Starlight it receives, relative to what Earth gets from the Sun.
    let insolationEarths: Double?
    let discoveryYear: Int?
    let discoveryMethod: String?
}
