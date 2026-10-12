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
    var header: FactHeader?
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
    var localGroup: LocalGroup?
    /// The naked-eye star a planet host is, if it's one, for its proper name.
    var brightStar: NakedEyeStar?
    var constellation: ConstellationProfile?
    /// How many stars with planets lie in the constellation.
    var constellationHosts: Int?
    var boundaries: ConstellationBoundaries?
}

enum FactSheetBuilder {
    static func sheet(for subject: FactSubject, data: FactSheetData) -> FactSheet {
        switch subject {
        case .laniakea: return laniakea(data.map)
        case .group(let g): return group(g, data.groupDetails, data.boundaries)
        case .galaxy(let g, let groupName): return galaxy(g, groupName: groupName, data.galaxyDetails, data.boundaries)
        case .localGroup: return localGroup(data.localGroup)
        case .localGroupGalaxy(let g): return localGroupGalaxy(g, data.localGroup, data.boundaries)
        case .milkyWay: return milkyWay(data.systems, sun: data.sun, colors: data.galaxyColors)
        case .starSystem(let s): return star(s, data.starDetails, data.boundaries, brightStar: data.brightStar)
        case .nakedEyeStar(let s): return nakedEyeStar(s, data.boundaries)
        case .constellation(let abbreviation): return constellation(abbreviation, data.constellation, hosts: data.constellationHosts)
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
        let what = g.isCluster ? "A galaxy cluster" : (g.galaxyCount > 1 ? "A group of galaxies" : "A galaxy with no measured neighbours")
        let place = g.isOnBoundary ? "on Laniakea's edge" : "in Laniakea"
        var sheet = FactSheet(
            title: g.name,
            summary: "\(what) \(place), \(GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)) away.",
            source: "Cosmicflows-4 (Tully et al. 2023). Names: SIMBAD. Color: RC3."
        )
        sheet.facts = [
            .init(label: "Galaxies with distances", value: g.galaxyCount.formatted()),
            .init(label: "Distance", value: mpc(g.distanceMpc, error: details?.distanceErrorMpc),
                  detail: GraphBuilder.lightYearsText(parsecs: g.distanceMpc * 1e6)),
        ]
        if let v = details?.velocityKmS { sheet.facts.append(lineOfSight(v)) }
        // Measured against the cosmic background; for nearby groups that is mostly our own motion.
        if g.distanceMpc >= 30, let v = details?.peculiarVelocityKmS {
            let error = details?.peculiarVelocityErrorKmS.map { " ± \($0.formatted(.number.precision(.fractionLength(0))))" } ?? ""
            sheet.facts.append(.init(
                label: "Peculiar velocity", value: "\(v >= 0 ? "+" : "−")\(abs(v).formatted(.number.precision(.fractionLength(0))))\(error) km/s",
                detail: "motion beyond the expansion, against the cosmic background"
            ))
        }
        sheet.facts.append(.init(label: "In Laniakea", value: g.isOnBoundary ? "On the edge" : "Inside"))
        // About 1 Mpc of space around the group's centre: wide for Virgo, narrow far away.
        let sky = SkyCoordinates.spherical(SkyCoordinates.equatorial(supergalactic: g.position))
        let fov = min(max(1 / g.distanceMpc * 180 / .pi, 0.2), 4)
        var photo = CelestialPhotos.sky(raDeg: sky.l, decDeg: sky.b, fovDegrees: fov)
        photo.caption = "\(photo.caption ?? ""), about 3 million light-years at its distance"
        sheet.header = .photo(photo)
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
        // Framed at twice its measured width, once SIMBAD's size has arrived; drawn from its
        // measurements if the photo can't load.
        if let details {
            let sky = SkyCoordinates.spherical(SkyCoordinates.equatorial(supergalactic: g.position))
            let fov = max((details.majorAxisArcmin ?? 4) * 2 / 60, 0.08)
            var photo = CelestialPhotos.sky(raDeg: sky.l, decDeg: sky.b, fovDegrees: fov)
            photo.fallback = .galaxyModel(galaxyModel(g, details))
            sheet.header = .photo(photo)
        }
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

    static func galaxyModel(_ g: Galaxy, _ details: GalaxyDetails) -> FactHeader.GalaxyModel {
        let morphology = details.morphology ?? g.morphology
        let ratio = details.minorAxisArcmin.flatMap { minor in details.majorAxisArcmin.map { minor / $0 } } ?? 1
        // The stage letter after S (and an optional bar or ring note), as in "SAB(rs)bc" → b.
        let stage = morphology.flatMap { $0.firstMatch(of: #/^[a-z]*S[AB]*(?:\([^)]*\))?([abcdm])/#).map { $0.1.first } } ?? nil
        return .init(type: GalaxyType(morphology: morphology), stage: stage, axisRatio: min(max(ratio, 0.08), 1),
                     positionAngleDeg: details.positionAngleDeg ?? 0, bMinusV: g.color?.bMinusV, seed: g.id)
    }

    /// A constellation: its size, stars and planets, with a real wide photo and its IAU boundary.
    static func constellation(_ abbreviation: String, _ profile: ConstellationProfile?, hosts: Int?) -> FactSheet {
        let name = Constellation.name(abbreviation)
        var sheet = FactSheet(
            title: name,
            summary: "One of the 88 official regions of the sky, fixed by the IAU in 1930.",
            source: "Boundaries: IAU (Delporte 1930, Roman 1987). Stars: Yale Bright Star Catalogue, Hipparcos. Photo: DSS2 via CDS."
        )
        guard let profile else { return sheet }
        // Its stars carry the constellation's Latin genitive, as Betelgeuse is α Orionis.
        if let example = profile.stars.first(where: { $0.designation?.contains(" ") == true && $0.properName != nil }),
           let designation = example.designation {
            sheet.summary += " Its stars are named with \(Constellation.genitives[abbreviation] ?? name), as \(example.name) is \(designation)."
        }
        var photo = CelestialPhotos.sky(raDeg: profile.centreRA, decDeg: profile.centreDec, fovDegrees: profile.fovDegrees, projection: "ARC")
        photo.overlay = profile.chart
        photo.fallback = .skyChart(profile.chart)
        sheet.header = .photo(photo)
        sheet.facts.append(.init(label: "Area", value: "\(profile.areaSquareDegrees.formatted(.number.precision(.fractionLength(0)))) square degrees",
                                 detail: "\((profile.areaSquareDegrees / 41_253 * 100).formatted(.number.precision(.significantDigits(2))))% of the sky"))
        sheet.facts.append(.init(label: "Stars you can see", value: profile.stars.count.formatted(), detail: "magnitude 6 or brighter"))
        if let brightest = profile.stars.first {
            sheet.facts.append(.init(label: "Brightest star", value: brightest.name, detail: "magnitude \(brightest.magnitude.formatted(.number.precision(.fractionLength(1))))"))
        }
        if let nearest = profile.stars.filter({ $0.distanceParsecs != nil }).min(by: { $0.distanceParsecs! < $1.distanceParsecs! }) {
            sheet.facts.append(.init(label: "Nearest of them", value: nearest.name, detail: GraphBuilder.lightYearsText(parsecs: nearest.distanceParsecs!)))
        }
        if let hosts { sheet.facts.append(.init(label: "Stars with planets", value: hosts.formatted(), detail: "confirmed, any brightness")) }
        let named = profile.stars.compactMap(\.properName)
        sheet.facts.append(.init(label: "Named stars", value: named.count.formatted(), detail: "official IAU names"))
        let top = profile.stars.prefix(6).map { "\($0.name) · magnitude \($0.magnitude.formatted(.number.precision(.fractionLength(1))))" }
        if !top.isEmpty { sheet.lists.append(.init(title: "Brightest stars", items: Array(top))) }
        sheet.notes.append("The photo is a real sky-survey image; the outline and names are drawn on it from the IAU boundaries and the star catalog.")
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

    static func star(_ s: StarSystem, _ d: StarDetails?, _ boundaries: ConstellationBoundaries?, brightStar: NakedEyeStar? = nil) -> FactSheet {
        let kind = ObjectKind.star(spectralType: d?.spectralType ?? s.spectralType, temperatureK: d?.temperatureK ?? s.temperatureK)
        let planets = s.planetCount == 1 ? "1 confirmed planet" : "\(s.planetCount) confirmed planets"
        var sheet = FactSheet(
            title: brightStar?.properName ?? s.name,
            summary: "\(starNoun(kind, spectralType: d?.spectralType ?? s.spectralType)) \(GraphBuilder.lightYearsText(parsecs: s.distanceParsecs)) away, with \(planets).",
            source: brightStar?.properName != nil ? "NASA Exoplanet Archive. Name: IAU." : "NASA Exoplanet Archive."
        )
        if let bright = brightStar, bright.properName != nil {
            sheet.facts.append(.init(label: "Also called", value: bright.designation ?? s.name, detail: bright.designation != nil ? s.name : nil))
        }
        sheet.temperatureK = d?.temperatureK ?? s.temperatureK
        if let r = d?.radiusSuns {
            sheet.header = .toScale(withSun(name: sheet.title, radiusSuns: r, temperatureK: sheet.temperatureK))
        }
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

    /// "A red supergiant", "An orange giant", "A Sun-like star": the temperature class sets the color
    /// word and the luminosity class in the spectral type (Ia…V) sets the size word. Without a
    /// luminosity class only the color is named, since an M star can be a dwarf or a supergiant.
    private static func starNoun(_ kind: ObjectKind, spectralType: String?) -> String {
        switch kind {
        case .brownDwarf: return "A brown dwarf"
        case .whiteDwarf: return "A white dwarf"
        default: break
        }
        let color: String
        switch kind {
        // The hot classes look different: O blue, B blue-white, A white (Sirius, Vega).
        case .hotStar:
            switch spectralType?.first(where: \.isUppercase) {
            case "O": color = "blue"
            case "A": color = "white"
            default: color = "blue-white"
            }
        case .fStar: color = "yellow-white"
        case .gStar: color = "yellow"
        case .kStar: color = "orange"
        case .mStar: color = "red"
        default: return "A star"
        }
        let noun: String
        switch luminosityClass(spectralType) {
        case "I": noun = "\(color) supergiant"
        case "II": noun = "\(color) bright giant"
        case "III": noun = "\(color) giant"
        case "IV": noun = "\(color) subgiant"
        case "V": noun = kind == .gStar ? "Sun-like star" : kind == .mStar ? "red dwarf" : kind == .kStar ? "orange dwarf" : "\(color) main-sequence star"
        default: noun = "\(color) star"
        }
        return (noun.first.map { "AEIOU".contains($0.uppercased()) } == true ? "An " : "A ") + noun
    }

    /// The luminosity class of a spectral type such as "M1-2Ia-Iab" → "I", "K0IIIb" → "III", "A1Vm" → "V".
    static func luminosityClass(_ spectralType: String?) -> String? {
        guard let t = spectralType,
              let m = t.firstMatch(of: #/^[a-z]*[OBAFGKM][0-9.]*(?:[-/][0-9.]+)?[:+]?\s*(IV|V|I{1,3})/#)
        else { return nil }
        return String(m.1)
    }

    static func nakedEyeStar(_ s: NakedEyeStar, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        let kind = ObjectKind.star(spectralType: s.spectralType, temperatureK: s.temperatureK)
        // One rounding for the summary and the distance cell, so they agree; uncertain distances are
        // rounded to two figures ("500 ± 60").
        var distanceText: String?, summaryDistance = ""
        if let d = s.distanceParsecs {
            let ly = d * 3.2616, error = (s.distanceErrorParsecs ?? 0) * 3.2616
            let rounded = ly.formatted(.number.precision(.significantDigits(2)))
            distanceText = error >= 1
                ? "\(rounded) ± \(error.formatted(.number.precision(.significantDigits(1)))) light-years"
                : GraphBuilder.lightYearsText(parsecs: d)
            summaryDistance = error >= 1 ? " about \(rounded) light-years away" : " \(GraphBuilder.lightYearsText(parsecs: d)) away"
        }
        var sheet = FactSheet(
            title: s.name,
            summary: "\(starNoun(kind, spectralType: s.spectralType))\(summaryDistance), bright enough to see with your eyes. No planets are known around it.",
            source: "Yale Bright Star Catalogue, Hipparcos (van Leeuwen 2007), JMMC Stellar Diameters Catalogue, PASTEL, IAU star names."
        )
        sheet.temperatureK = s.temperatureK
        if let r = s.radiusSuns {
            sheet.header = .toScale(withSun(name: s.name, radiusSuns: r, temperatureK: s.temperatureK))
        }
        if let designation = s.designation, s.properName != nil {
            sheet.facts.append(.init(label: "Also called", value: designation))
        }
        if let value = distanceText {
            sheet.facts.append(.init(label: "Distance", value: value, detail: "from its Hipparcos parallax"))
        } else {
            sheet.facts.append(.init(label: "Distance", value: "Not well measured", detail: "too far for a precise parallax"))
        }
        if let type = s.spectralType { sheet.facts.append(.init(label: "Spectral type", value: type)) }
        if let t = s.temperatureK {
            sheet.facts.append(.init(
                label: "Surface temperature", value: "\(s.measuredTemperatureK == nil ? "≈ " : "")\(t.formatted(.number.precision(.fractionLength(0)))) K",
                detail: s.measuredTemperatureK == nil ? "estimated from its color" : "median of published measurements"
            ))
        }
        if let r = s.radiusSuns { sheet.facts.append(.init(label: "Width", value: "\(times(r)) × Sun", detail: "from its measured angular size")) }
        if let l = s.visualLuminositySuns {
            // An estimate (no dust correction), so two figures at most.
            sheet.facts.append(.init(label: "Shines like", value: "≈ \(l.formatted(.number.precision(.significantDigits(2)))) Suns", detail: "in visible light"))
        }
        sheet.facts.append(.init(label: "From Earth", value: "Magnitude \(s.magnitude.formatted(.number.precision(.fractionLength(1))))"))
        if let c = boundaries?.constellation(of: SkyCoordinates.cartesian(longitudeDeg: s.raDeg, latitudeDeg: s.decDeg, distance: 1)) {
            sheet.facts.append(.init(label: "Constellation", value: Constellation.name(c)))
        }
        if s.measuredTemperatureK == nil, s.temperatureK != nil {
            sheet.notes.append("Temperatures estimated from color run low for giant stars.")
        }
        return sheet
    }

    static func sun(_ d: SunDetails?) -> FactSheet {
        var sheet = FactSheet(title: "Sun", summary: "The star at the centre of the Solar System.", source: "NASA JPL Horizons.")
        if var photo = CelestialPhotos.solarSystem["10"] {
            photo.fallback = .toScale([.init(name: "Sun", radius: 1, look: .star(temperatureK: 5772))])
            sheet.header = .photo(photo)
        }
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

    /// A star beside the Sun at true relative size.
    private static func withSun(name: String, radiusSuns: Double, temperatureK: Double?) -> [FactHeader.ScaleBody] {
        [.init(name: name, radius: radiusSuns, look: .star(temperatureK: temperatureK)),
         // 5,772 K is the IAU 2015 nominal solar effective temperature.
         .init(name: "Sun", radius: 1, look: .star(temperatureK: 5772))]
    }

    private static func colorFact(_ color: GalaxyColor, whose: String?) -> FactSheet.Fact {
        let source = color.isMeasured ? "measured" : "typical of \(color.typeName.map { $0 == "dwarfSpheroidal" ? "dwarf spheroidal" : $0 } ?? "its type")s"
        return .init(label: "Color (B−V)", value: color.bMinusV.formatted(.number.precision(.fractionLength(2))),
                     detail: whose.map { "\($0), \(source)" } ?? source)
    }

    /// Andromeda is coming toward us at 300 km/s; Virgo's galaxies move away at over 1,000.
    static func lineOfSight(_ v: Double) -> FactSheet.Fact {
        .init(label: v < 0 ? "Coming toward us at" : "Moving away at",
              value: "\(abs(v).formatted(.number.precision(.fractionLength(0)))) km/s", detail: "as seen from the Sun")
    }

    static func constellation(_ direction: SIMD3<Double>, _ boundaries: ConstellationBoundaries?) -> String? {
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

    static func times(_ value: Double) -> String {
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
