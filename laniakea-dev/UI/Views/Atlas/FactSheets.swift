import Foundation
import simd

/// The contents of a fact sheet. Every value comes from a catalog or is computed from one.
struct FactSheet {
    struct Fact: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        var detail: String?
    }

    struct List: Identifiable {
        var id: String { title }
        let title: String
        let items: [String]
    }

    var title: String
    var summary: String
    var facts: [Fact] = []
    var lists: [List] = []
    var notes: [String] = []
    var source: String
    /// For stars: surface temperature, which colors the dot beside the title.
    var temperatureK: Double?
}

/// Everything a fact sheet can draw on; the extra pieces arrive as they load.
struct FactSheetData {
    var map: LaniakeaMap?
    var groupDetails: GroupDetails?
    var galaxyDetails: GalaxyDetails?
    var systems: [StarSystem]?
    var starDetails: StarDetails?
    var sun: SunDetails?
    var galaxyColors: GalaxyColors?
    var boundaries: ConstellationBoundaries?
}

enum FactSheetBuilder {
    static func sheet(for subject: FactSubject, data: FactSheetData) -> FactSheet {
        switch subject {
        case .laniakea: return laniakea(data.map)
        case .group(let g): return group(g, data.groupDetails, data.boundaries)
        case .galaxy(let g, let groupName): return galaxy(g, groupName: groupName, data.galaxyDetails, data.boundaries)
        case .milkyWay: return milkyWay(data.systems, sun: data.sun, colors: data.galaxyColors)
        case .starSystem(let s): return star(s, data.starDetails, data.boundaries)
        case .sun: return sun(data.sun)
        }
    }

    // MARK: Laniakea

    static func laniakea(_ map: LaniakeaMap?) -> FactSheet {
        var sheet = FactSheet(
            title: "Laniakea",
            summary: "Our home supercluster. Every galaxy in it is drifting toward the same region of space; "
                + "its edge is where the flow of galaxies divides. The name is Hawaiian for “immeasurable heaven”.",
            source: "Boundary: Dupuy & Courtois (2023). Galaxies: Cosmicflows-4 (Tully et al. 2023). Names: SIMBAD."
        )
        guard let map else { return sheet }
        let inside = map.groups.filter { !$0.isOnBoundary }
        sheet.facts = [
            .init(label: "Longest span", value: mpc(map.longestSpanMpc), detail: GraphBuilder.lightYearsText(parsecs: map.longestSpanMpc * 1e6)),
            .init(label: "Volume", value: "\(compact(map.volumeMpc3)) Mpc³"),
            .init(label: "Galaxy groups inside", value: inside.count.formatted(), detail: "\((map.groups.count - inside.count).formatted()) more on the edge"),
            .init(label: "Galaxies with distances", value: inside.map(\.galaxyCount).reduce(0, +).formatted(), detail: "in Cosmicflows-4"),
            .init(label: "Clusters", value: inside.filter(\.isCluster).count.formatted(),
                  detail: "named in SIMBAD; \(map.groups.filter { $0.isCluster && $0.isOnBoundary }.count) more on the edge"),
            .init(label: "Milky Way from its centre", value: mpc(simd_length(map.centre)), detail: GraphBuilder.lightYearsText(parsecs: simd_length(map.centre) * 1e6)),
        ]
        if let richest = inside.max(by: { $0.galaxyCount < $1.galaxyCount }) {
            sheet.facts.append(.init(label: "Richest", value: richest.name, detail: "\(richest.galaxyCount) galaxies with distances"))
        }
        sheet.notes = [
            "The boundary map is made of cells \(GraphBuilder.distanceNumber(map.cellSizeMpc)) Mpc wide, so the edge is only that sharp.",
            "Counts include only galaxies whose distances have been measured; Laniakea holds far more.",
        ]
        return sheet
    }

    // MARK: Groups and galaxies

    static func group(_ g: GalaxyGroup, _ details: GroupDetails?, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        // We're inside the Local Group, so its distance and motion relative to us mean something else.
        let isHome = g.id == GalaxyGroup.localGroupID
        let what = g.isCluster ? "A galaxy cluster" : (g.galaxyCount > 1 ? "A group of galaxies" : "A galaxy with no measured neighbours")
        let place = g.isOnBoundary ? "on Laniakea's edge" : "in Laniakea"
        var sheet = FactSheet(
            title: g.name,
            summary: isHome
                ? "Our home group: the Milky Way, Andromeda, the Triangulum Galaxy and dozens of smaller galaxies."
                : "\(what) \(place), \(GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)) away.",
            source: "Cosmicflows-4 (Tully et al. 2023). Names: SIMBAD. Color: RC3."
        )
        sheet.facts = [
            .init(label: "Galaxies with distances", value: g.galaxyCount.formatted(), detail: isHome ? "besides the Milky Way" : nil),
            .init(label: isHome ? "Distance to its centre" : "Distance", value: mpc(g.distanceMpc, error: details?.distanceErrorMpc),
                  detail: GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)),
        ]
        if !isHome, let v = details?.velocityKmS { sheet.facts.append(lineOfSight(v)) }
        // Measured against the cosmic background; for nearby groups that is mostly our own motion.
        if !isHome, g.distanceMpc >= 30, let v = details?.peculiarVelocityKmS {
            let error = details?.peculiarVelocityErrorKmS.map { " ± \($0.formatted(.number.precision(.fractionLength(0))))" } ?? ""
            sheet.facts.append(.init(
                label: "Peculiar velocity", value: "\(v >= 0 ? "+" : "−")\(abs(v).formatted(.number.precision(.fractionLength(0))))\(error) km/s",
                detail: "motion beyond the expansion, against the cosmic background"
            ))
        }
        sheet.facts.append(.init(label: "In Laniakea", value: g.isOnBoundary ? "On the edge" : "Inside"))
        if let color = g.color {
            sheet.facts.append(colorFact(color, whose: "its brightest galaxy"))
            sheet.temperatureK = GraphBuilder.colorTemperature(color)
        }
        if let c = constellation(SkyCoordinates.equatorial(supergalactic: g.position), boundaries) {
            sheet.facts.append(.init(label: "Constellation", value: c))
        }
        if let methods = details?.methods, !methods.isEmpty {
            sheet.lists.append(.init(title: "How its distance was measured", items: methods.map { m in
                m.galaxies.map { "\(m.method.name): \($0) \($0 == 1 ? "galaxy" : "galaxies")" } ?? m.method.name
            }))
        }
        if details != nil { sheet.notes.append("Uncertainties are the catalog's statistical errors.") }
        return sheet
    }

    static func galaxy(_ g: Galaxy, groupName: String, _ details: GalaxyDetails?, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        let morphology = details?.morphology ?? g.morphology
        let kind = ObjectKind.galaxy(morphology: morphology)
        var sheet = FactSheet(
            title: g.name,
            summary: "\(galaxyNoun(kind)) in the \(groupName), \(GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)) away.",
            source: "Distance: Cosmicflows-4 (Tully et al. 2023). Type and size: SIMBAD. Color: RC3."
        )
        if let morphology {
            sheet.facts.append(.init(label: "Type", value: kind == .unknownGalaxy ? morphology : String(kind.label.dropLast()), detail: kind == .unknownGalaxy ? nil : morphology))
        }
        sheet.facts.append(.init(label: "Distance", value: mpc(g.distanceMpc, error: g.distanceErrorMpc), detail: GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)))
        if let arcmin = details?.majorAxisArcmin, arcmin > 0 {
            let parsecs = g.distanceMpc * 1e6 * arcmin / 60 * .pi / 180
            sheet.facts.append(.init(label: "Visible width", value: GraphBuilder.lightYearsText(parsecs: parsecs), detail: "\(arcmin.formatted(.number.precision(.significantDigits(3))))′ across on the sky"))
        }
        if let v = details?.velocityKmS { sheet.facts.append(lineOfSight(v)) }
        if let color = g.color {
            sheet.facts.append(colorFact(color, whose: nil))
            sheet.temperatureK = GraphBuilder.colorTemperature(color)
        }
        if let c = constellation(SkyCoordinates.equatorial(supergalactic: g.position), boundaries) {
            sheet.facts.append(.init(label: "Constellation", value: c))
        }
        sheet.facts.append(.init(label: "Known planets", value: "None", detail: "none confirmed beyond the Milky Way yet"))
        if let methods = details?.methods, !methods.isEmpty {
            sheet.lists.append(.init(title: "How its distance was measured", items: methods.map(\.name)))
        }
        sheet.notes.append("Visible width is the galaxy's catalogued size on the sky at its measured distance; its faint outskirts reach farther.")
        return sheet
    }

    private static func galaxyNoun(_ kind: ObjectKind) -> String {
        switch kind {
        case .spiral: return "A spiral galaxy"
        case .lenticular: return "A lenticular galaxy"
        case .elliptical: return "An elliptical galaxy"
        case .irregular: return "An irregular galaxy"
        case .dwarfSpheroidal: return "A dwarf spheroidal galaxy"
        default: return "A galaxy"
        }
    }

    // MARK: Milky Way and stars

    static func milkyWay(_ systems: [StarSystem]?, sun: SunDetails?, colors: GalaxyColors?) -> FactSheet {
        var sheet = FactSheet(
            title: "Milky Way",
            summary: "Our galaxy, one of the two largest in the Local Group. From inside it we can't see its whole shape, "
                + "so Atlas maps the stars in it that are known to have planets.",
            source: "NASA Exoplanet Archive. Sun's motion: NASA JPL Horizons."
        )
        if let systems, !systems.isEmpty {
            sheet.facts = [
                .init(label: "Stars with planets", value: systems.count.formatted(), detail: "with measured distances"),
                .init(label: "Their planets", value: systems.map(\.planetCount).reduce(0, +).formatted(), detail: "confirmed"),
            ]
            if let nearest = systems.min(by: { $0.distanceParsecs < $1.distanceParsecs }) {
                sheet.facts.append(.init(label: "Nearest", value: nearest.name, detail: GraphBuilder.lightYearsText(parsecs: nearest.distanceParsecs)))
            }
            if let farthest = systems.max(by: { $0.distanceParsecs < $1.distanceParsecs }) {
                sheet.facts.append(.init(label: "Farthest", value: farthest.name, detail: GraphBuilder.lightYearsText(parsecs: farthest.distanceParsecs)))
            }
            if let most = systems.max(by: { $0.planetCount < $1.planetCount }) {
                sheet.facts.append(.init(label: "Most planets", value: most.name, detail: "\(most.planetCount) planets"))
            }
            let kinds = ObjectKind.counts(systems.map { ObjectKind.star(spectralType: $0.spectralType, temperatureK: $0.temperatureK) })
            sheet.lists.append(.init(title: "Stars with planets, by type", items: kinds.map { "\($0.kind.label): \($0.count.formatted())" }))
        }
        if let speed = sun?.speedCosmicBackgroundKmS {
            sheet.facts.append(.init(label: "Sun's speed", value: "\(speed.formatted()) km/s", detail: "relative to the cosmic background"))
        }
        if let bv = colors?.typical[.spiral] {
            let color = GalaxyColor(bMinusV: bv, isMeasured: false, typeName: "spiral")
            sheet.facts.append(colorFact(color, whose: nil))
            sheet.temperatureK = GraphBuilder.colorTemperature(color)
            sheet.notes.append("We can't measure our own galaxy's color from inside it, so it's shown with the typical color of a spiral like it.")
        }
        sheet.notes.append("Star types come from each star's spectral type, or its temperature when that isn't recorded.")
        return sheet
    }

    static func star(_ s: StarSystem, _ d: StarDetails?, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        let kind = ObjectKind.star(spectralType: d?.spectralType ?? s.spectralType, temperatureK: d?.temperatureK ?? s.temperatureK)
        let planets = s.planetCount == 1 ? "1 confirmed planet" : "\(s.planetCount) confirmed planets"
        var sheet = FactSheet(
            title: s.name,
            summary: "\(starNoun(kind)) \(GraphBuilder.lightYearsText(parsecs: s.distanceParsecs)) away, with \(planets).",
            source: "NASA Exoplanet Archive."
        )
        sheet.temperatureK = d?.temperatureK ?? s.temperatureK
        sheet.facts.append(.init(label: "Distance", value: GraphBuilder.lightYearsText(parsecs: s.distanceParsecs), detail: "\(s.distanceParsecs.formatted(.number.precision(.significantDigits(3)))) parsecs"))
        if let type = d?.spectralType ?? s.spectralType { sheet.facts.append(.init(label: "Spectral type", value: type)) }
        if let t = d?.temperatureK ?? s.temperatureK { sheet.facts.append(.init(label: "Surface temperature", value: "\(t.formatted(.number.precision(.fractionLength(0)))) K")) }
        if let r = d?.radiusSuns { sheet.facts.append(.init(label: "Size", value: "\(times(r)) × Sun")) }
        if let m = d?.massSuns { sheet.facts.append(.init(label: "Mass", value: "\(times(m)) × Sun")) }
        if let l = d?.logLuminositySuns { sheet.facts.append(.init(label: "Brightness", value: "\(times(pow(10, l))) × Sun")) }
        if let age = d?.ageGyr { sheet.facts.append(.init(label: "Age", value: "\(times(age)) billion years")) }
        if let met = d?.metallicity { sheet.facts.append(.init(label: "Metal content", value: "\(times(pow(10, met))) × Sun")) }
        if let n = d?.starCount, n > 1 { sheet.facts.append(.init(label: "Stars in its system", value: "\(n)")) }
        if let v = d?.apparentMagnitude {
            let seen = v < 6 ? "visible to the naked eye" : (v < 9.5 ? "visible in binoculars" : "needs a telescope")
            sheet.facts.append(.init(label: "Brightness from Earth", value: "Magnitude \(v.formatted(.number.precision(.fractionLength(1))))", detail: seen))
        }
        if let c = constellation(SkyCoordinates.equatorial(galactic: s.position), boundaries) {
            sheet.facts.append(.init(label: "Constellation", value: c))
        }
        sheet.facts.append(.init(label: "Planets", value: "\(s.planetCount)", detail: "confirmed"))
        return sheet
    }

    private static func starNoun(_ kind: ObjectKind) -> String {
        switch kind {
        case .hotStar: return "A hot star"
        case .fStar: return "An F-type star"
        case .gStar: return "A Sun-like star"
        case .kStar: return "A K-type star"
        case .mStar: return "A red dwarf"
        case .brownDwarf: return "A brown dwarf"
        case .whiteDwarf: return "A white dwarf"
        default: return "A star"
        }
    }

    static func sun(_ d: SunDetails?) -> FactSheet {
        var sheet = FactSheet(title: "Sun", summary: "The star at the centre of the Solar System.", source: "NASA JPL Horizons.")
        guard let d else { return sheet }
        sheet.temperatureK = d.effectiveTemperatureK
        if let r = d.radiusKm { sheet.facts.append(.init(label: "Diameter", value: "\((r * 2).formatted(.number.precision(.fractionLength(0)))) km")) }
        if let m = d.massKg { sheet.facts.append(.init(label: "Mass", value: scientific(m, unit: "kg"))) }
        if let t = d.effectiveTemperatureK { sheet.facts.append(.init(label: "Surface temperature", value: "\(t.formatted()) K")) }
        if let l = d.luminosityWatts { sheet.facts.append(.init(label: "Power output", value: scientific(l, unit: "W"))) }
        if let rho = d.densityGramsPerCm3 { sheet.facts.append(.init(label: "Density", value: "\(rho.formatted()) g/cm³")) }
        if let g = d.surfaceGravity { sheet.facts.append(.init(label: "Surface gravity", value: "\(g.formatted()) m/s²")) }
        if let v = d.escapeSpeedKmS { sheet.facts.append(.init(label: "Escape speed", value: "\(v.formatted()) km/s")) }
        if let p = d.rotationDays {
            sheet.facts.append(.init(label: "Spins once every", value: "\(p.formatted()) days", detail: "faster at its equator, slower near the poles"))
        }
        if let tilt = d.axialTiltDeg { sheet.facts.append(.init(label: "Axial tilt", value: "\(tilt.formatted())°", detail: "to Earth's orbit")) }
        if let v = d.speedNearbyStarsKmS { sheet.facts.append(.init(label: "Speed among nearby stars", value: "\(v.formatted()) km/s")) }
        if let v = d.speedCosmicBackgroundKmS { sheet.facts.append(.init(label: "Speed through the universe", value: "\(v.formatted()) km/s", detail: "relative to the cosmic background")) }
        return sheet
    }

    // MARK: Formatting

    private static func colorFact(_ color: GalaxyColor, whose: String?) -> FactSheet.Fact {
        let source = color.isMeasured ? "measured" : "typical of \(color.typeName.map { $0 == "dwarfSpheroidal" ? "dwarf spheroidal" : $0 } ?? "its type")s"
        return .init(label: "Color (B−V)", value: color.bMinusV.formatted(.number.precision(.fractionLength(2))),
                     detail: whose.map { "\($0), \(source)" } ?? source)
    }

    /// Andromeda is coming toward us at 300 km/s; Virgo's galaxies move away at over 1,000.
    private static func lineOfSight(_ v: Double) -> FactSheet.Fact {
        .init(label: v < 0 ? "Coming toward us at" : "Moving away at",
              value: "\(abs(v).formatted(.number.precision(.fractionLength(0)))) km/s", detail: "as seen from the Sun")
    }

    private static func constellation(_ direction: SIMD3<Double>, _ boundaries: ConstellationBoundaries?) -> String? {
        boundaries?.constellation(of: direction).map(Constellation.name)
    }

    /// "16.2 ± 0.1 Mpc": the value and its error to the same decimal place.
    private static func mpc(_ value: Double, error: Double? = nil) -> String {
        let digits = value < 1 ? 2 : (value < 10 || (error ?? 1) < 1 ? 1 : 0)
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits))
        let e = error.map { " ± \(max($0, pow(10, -Double(digits))).formatted(format))" } ?? ""
        return "\(value.formatted(format))\(e) Mpc"
    }

    private static func compact(_ value: Double) -> String {
        value >= 1e6 ? "\((value / 1e6).formatted(.number.precision(.significantDigits(2)))) million" : value.formatted(.number.precision(.significantDigits(2)))
    }

    private static func times(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(value < 10 ? 2 : 3)))
    }

    /// e.g. 1.99 × 10³⁰ kg
    static func scientific(_ value: Double, unit: String) -> String {
        let exponent = Int(floor(log10(value)))
        let mantissa = value / pow(10, Double(exponent))
        let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        let power = String(String(exponent).compactMap { superscripts[$0] })
        return "\(mantissa.formatted(.number.precision(.fractionLength(2)))) × 10\(power) \(unit)"
    }
}
