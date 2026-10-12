import Foundation

extension FactSheetBuilder {
    /// A black hole: its mass from every published method, its distance and how sure each is.
    static func blackHole(_ h: BlackHole, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        let distance = BlackHoleText.distance(h)
        let away = distance.map { " \($0) away" } ?? ""
        let summary: String
        switch h.setting {
        case .galacticCentre:
            summary = "The supermassive black hole at the centre of the Milky Way,\(away). Stars race around it on tight orbits, and those orbits weigh it."
        case .galaxyCentre:
            summary = "The supermassive black hole at the heart of \(h.aliases.last ?? "its galaxy"),\(away). Its mass comes from how fast the stars or gas around it move."
        case .xRayTransient:
            summary = (h.isConfirmed ? "A black hole" : "A likely black hole")
                + " in a binary star\(h.distanceParsecs == nil ? "" : ",\(away)"). Now and then it pulls gas off its companion and flares up in X-rays."
        case .xRayPersistent:
            summary = "A black hole in a binary star,\(away). It feeds on its companion's wind and shines steadily in X-rays."
        case .dormantBinary:
            summary = "A quiet black hole in a binary star,\(away). Gaia found it from the wobble of the star orbiting it."
        }
        var sheet = FactSheet(title: h.name, summary: summary, source: h.sources.joined(separator: ". ") + ".")
        var photo = CelestialPhotos.sky(raDeg: h.raDeg, decDeg: h.decDeg, fovDegrees: h.setting == .galacticCentre ? 0.25 : 0.1)
        photo.caption = "\(photo.caption ?? ""), centred on it. The black hole itself can't be seen"
            + (h.kind == .stellar && h.setting != .xRayTransient ? "; the star there is its companion" : "")
        sheet.header = .photo(photo)

        sheet.facts.append(.init(label: "Type", value: h.kind == .supermassive ? "Supermassive black hole" : "Stellar-mass black hole",
                                 detail: h.isConfirmed ? nil : "candidate: not yet weighed"))
        for (i, m) in h.masses.enumerated() {
            sheet.facts.append(.init(label: i == 0 ? "Mass" : "Mass, another way", value: BlackHoleText.mass(m), detail: m.method))
        }
        if let f = h.massFunction {
            sheet.facts.append(.init(label: "At least", value: BlackHoleText.mass(BlackHole.Mass(suns: f.suns, plus: f.plus, minus: f.minus, method: f.method, source: f.source)),
                                     detail: "the mass function: the least it can weigh, whatever the orbit's tilt"))
        }
        if h.masses.isEmpty && h.massFunction == nil {
            sheet.facts.append(.init(label: "Mass", value: "Not measured", detail: "its companion's orbit hasn't been measured"))
        }
        if let distance {
            sheet.facts.append(.init(label: "Distance", value: distance, detail: h.distanceMethod))
        } else {
            sheet.facts.append(.init(label: "Distance", value: "Not measured", detail: "so it isn't on the map"))
        }
        if let m = h.masses.first, m.limit == .none, m.rangeTop == nil {
            // Schwarzschild radius r = 2GM/c² = 2.953 km per solar mass.
            let km = 2.953 * m.suns
            let text = km >= 1e6 ? "\((km / 1e6).formatted(.number.precision(.significantDigits(2)))) million km"
                : "\(km.formatted(.number.precision(.significantDigits(2)))) km"
            sheet.facts.append(.init(label: "Event horizon radius", value: "≈ \(text)", detail: "2GM/c² for its mass, if it doesn't spin"))
        }
        if let type = h.companionType { sheet.facts.append(.init(label: "Companion star", value: type, detail: "spectral type")) }
        if let p = h.orbitalPeriodDays {
            sheet.facts.append(.init(label: "Orbit", value: p < 2 ? "\((p * 24).formatted(.number.precision(.significantDigits(3)))) hours" : "\(p.formatted(.number.precision(.significantDigits(3)))) days"))
        }
        if let year = h.discoveryYear { sheet.facts.append(.init(label: "Found", value: String(year))) }
        if let c = boundaries?.constellation(of: SkyCoordinates.cartesian(longitudeDeg: h.raDeg, latitudeDeg: h.decDeg, distance: 1)) {
            sheet.facts.append(.init(label: "Constellation", value: Constellation.name(c)))
        }
        if h.aliases.count > 0 { sheet.lists.append(.init(title: "Also called", items: h.aliases)) }
        let measured = h.masses.map { "\($0.method): \($0.source)" } + (h.massFunction.map { ["Mass function: \($0.source)"] } ?? [])
        if !measured.isEmpty { sheet.lists.append(.init(title: "How it was weighed", items: measured)) }
        sheet.notes = h.notes + ["Black holes give off no light of their own; every value here comes from how they pull on the stars and gas around them."]
        if h.distanceLimit != .none {
            sheet.notes.append("≥ marks a minimum and ≈ a rough value, as the catalog gives them.")
        }
        return sheet
    }

    /// A galaxy's or the Milky Way's sheet with its central black hole added, when one is measured.
    static func withCentralBlackHole(_ sheet: FactSheet, _ h: BlackHole?) -> FactSheet {
        guard let h, let first = h.masses.first else { return sheet }
        var sheet = sheet
        sheet.facts.append(.init(label: "Central black hole", value: BlackHoleText.mass(first),
                                 detail: "\(h.setting == .galacticCentre ? "\(h.name), " : "")\(first.method)"))
        for m in h.masses.dropFirst() {
            sheet.facts.append(.init(label: "Its mass, another way", value: BlackHoleText.mass(m), detail: m.method))
        }
        if h.masses.count > 1 { sheet.notes.append("The two black-hole masses come from different methods and don't agree; both are published.") }
        sheet.source += " Black hole: \(h.masses.map(\.source).joined(separator: "; "))."
        return sheet
    }
}
