import Foundation

/// The kinds of object Atlas filters by. Each level of Atlas offers the kinds found there.
enum ObjectKind: String, CaseIterable, Hashable {
    // Laniakea
    case cluster, group, loneGalaxy
    // Galaxies, by Hubble type
    case spiral, lenticular, elliptical, irregular, dwarfSpheroidal, unknownGalaxy
    // Stars: which set they belong to, then spectral class
    case withPlanets, nakedEye
    case hotStar, fStar, gStar, kStar, mStar, brownDwarf, whiteDwarf, unknownStar
    // Planets around other stars, by size
    case earthSize, superEarth, neptuneSize, jupiterSize, largerThanJupiter, unknownSize
    // Solar System
    case rocky, giant

    var label: String {
        switch self {
        case .cluster: return "Clusters"
        case .group: return "Groups"
        case .loneGalaxy: return "Lone galaxies"
        case .spiral: return "Spirals"
        case .lenticular: return "Lenticulars"
        case .elliptical: return "Ellipticals"
        case .irregular: return "Irregulars"
        case .dwarfSpheroidal: return "Dwarf spheroidals"
        case .unknownGalaxy: return "Type unknown"
        case .withPlanets: return "With planets"
        case .nakedEye: return "Naked-eye stars"
        case .hotStar: return "Blue-white (O, B, A)"
        case .fStar: return "Yellow-white (F)"
        case .gStar: return "Yellow (G)"
        case .kStar: return "Orange (K)"
        case .mStar: return "Red (M)"
        case .brownDwarf: return "Brown dwarfs"
        case .whiteDwarf: return "White dwarfs"
        case .unknownStar: return "Type unknown"
        case .earthSize: return "Earth-size"
        case .superEarth: return "Super-Earths"
        case .neptuneSize: return "Neptune-size"
        case .jupiterSize: return "Jupiter-size"
        case .largerThanJupiter: return "Larger than Jupiter"
        case .unknownSize: return "Size unknown"
        case .rocky: return "Rocky planets"
        case .giant: return "Giant planets"
        }
    }

    /// Kinds in the same facet are alternatives (spirals or ellipticals); the filter combines facets
    /// with "and" (naked-eye stars that are also Sun-like).
    var facet: Int {
        switch self {
        case .withPlanets, .nakedEye: return 1
        default: return 0
        }
    }

    /// A typical temperature for a star class, for its color swatch.
    var swatchTemperature: Double? {
        switch self {
        case .hotStar: return 11_000
        case .fStar: return 6_500
        case .gStar: return 5_700
        case .kStar: return 4_500
        case .mStar: return 3_200
        case .brownDwarf: return 2_000
        case .whiteDwarf: return 9_000
        default: return nil
        }
    }

    /// A galaxy's broad type from its Hubble classification, such as "SAB(rs)bc" (spiral) or "E-E/S0".
    static func galaxy(morphology: String?) -> ObjectKind {
        switch GalaxyType(morphology: morphology) {
        case .spiral: return .spiral
        case .lenticular: return .lenticular
        case .elliptical: return .elliptical
        case .irregular: return .irregular
        case .dwarfSpheroidal: return .dwarfSpheroidal
        case nil: return .unknownGalaxy
        }
    }

    /// A star's class from its spectral type when known, else from its temperature using the
    /// main-sequence boundaries of Pecaut & Mamajek (2013).
    static func star(spectralType: String?, temperatureK: Double?) -> ObjectKind {
        if let type = spectralType?.trimmingCharacters(in: .whitespaces), !type.isEmpty {
            if type.hasPrefix("D") || type.contains("WD") { return .whiteDwarf }
            // Skip prefixes such as "sd" (subdwarf).
            if let letter = type.first(where: \.isUppercase) {
                switch letter {
                case "O", "B", "A": return .hotStar
                case "F": return .fStar
                case "G": return .gStar
                case "K": return .kStar
                case "M": return .mStar
                case "L", "T", "Y": return .brownDwarf
                default: break
                }
            }
        }
        guard let t = temperatureK else { return .unknownStar }
        switch t {
        case 7300...: return .hotStar
        case 5950..<7300: return .fStar
        case 5300..<5950: return .gStar
        case 3900..<5300: return .kStar
        case 2300..<3900: return .mStar
        default: return .brownDwarf
        }
    }

    /// Size classes used for Kepler's planets (Borucki et al. 2011), from radius in Earth radii.
    static func planet(radiusEarths: Double?) -> ObjectKind {
        guard let r = radiusEarths else { return .unknownSize }
        switch r {
        case ..<1.25: return .earthSize
        case 1.25..<2: return .superEarth
        case 2..<6: return .neptuneSize
        case 6..<15: return .jupiterSize
        default: return .largerThanJupiter
        }
    }

    /// How many of each kind, in the order kinds are listed above.
    static func counts(_ kinds: [ObjectKind]) -> [(kind: ObjectKind, count: Int)] {
        var counts: [ObjectKind: Int] = [:]
        for kind in kinds { counts[kind, default: 0] += 1 }
        return allCases.compactMap { kind in counts[kind].map { (kind, $0) } }
    }

    static func solarSystem(densityGramsPerCm3: Double?) -> ObjectKind? {
        PlanetComposition.solarSystem(densityGramsPerCm3: densityGramsPerCm3).map { $0 == .rocky ? .rocky : .giant }
    }

    /// The planet color a kind's chip shows, where every planet of that kind shares a makeup.
    var swatchComposition: PlanetComposition? {
        switch self {
        case .earthSize, .rocky: return .rocky
        case .neptuneSize, .jupiterSize, .largerThanJupiter, .giant: return .gasRich
        default: return nil
        }
    }
}

/// What Atlas shows: kinds of object (none selected shows all) and, optionally, one constellation.
struct AtlasFilter: Equatable {
    var kinds: Set<ObjectKind> = []
    /// IAU abbreviation, such as "Vir".
    var constellation: String?

    var isActive: Bool { !kinds.isEmpty || constellation != nil }

    func allows(kind: ObjectKind?, constellation: String?) -> Bool {
        allows(kinds: kind.map { [$0] } ?? [], constellation: constellation)
    }

    /// An object passes when, in every facet with a selection, it has one of the selected kinds.
    func allows(kinds objectKinds: [ObjectKind], constellation: String?) -> Bool {
        for facet in Set(kinds.map(\.facet)) where !objectKinds.contains(where: { $0.facet == facet && kinds.contains($0) }) {
            return false
        }
        if let wanted = self.constellation, constellation != wanted { return false }
        return true
    }
}

/// Something Atlas has a fact sheet for.
enum FactSubject: Identifiable, Hashable {
    case laniakea
    case group(GalaxyGroup)
    case galaxy(Galaxy, groupName: String)
    case localGroup
    case localGroupGalaxy(LocalGroupGalaxy)
    case milkyWay
    case starSystem(StarSystem)
    case nakedEyeStar(NakedEyeStar)
    /// One of the 88 constellations, by IAU abbreviation.
    case constellation(String)
    case sun

    var id: String {
        switch self {
        case .laniakea: return "laniakea"
        case .group(let g): return "group-\(g.id)"
        case .galaxy(let g, _): return "galaxy-\(g.id)"
        case .localGroup: return "local-group"
        case .localGroupGalaxy(let g): return "lg-\(g.id)"
        case .milkyWay: return "milky-way"
        case .starSystem(let s): return "star-\(s.id)"
        case .nakedEyeStar(let s): return "naked-\(s.id)"
        case .constellation(let abbreviation): return "constellation-\(abbreviation)"
        case .sun: return "sun"
        }
    }

    init(_ place: AtlasPlace) {
        switch place {
        case .laniakea: self = .laniakea
        case .group(let g): self = .group(g)
        case .localGroup: self = .localGroup
        case .milkyWay: self = .milkyWay
        case .starSystem(let s): self = .starSystem(s)
        case .solarSystem: self = .sun
        }
    }
}
