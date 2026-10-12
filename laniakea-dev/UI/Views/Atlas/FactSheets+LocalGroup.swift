import Foundation
import simd

extension FactSheetBuilder {
    // MARK: Local Group

    static func localGroup(_ group: LocalGroup?) -> FactSheet {
        var sheet = FactSheet(
            title: "Local Group",
            summary: "Our galaxy's group: the Milky Way, Andromeda and Triangulum, with the dwarf galaxies around them. "
                + "Their gravity holds them together, so space no longer expands between them.",
            source: "Local Volume Database (Pace 2025) and the papers it cites. Types: McConnachie (2012). Size: van den Bergh (1999)."
        )
        let radius = LocalGroup.zeroVelocityRadiusKpc
        sheet.notes.append("Members are the galaxies within \((radius / 1000).formatted()) ± 0.15 Mpc of its centre, the edge inside which galaxies have stopped moving apart with the universe (van den Bergh 1999). Dwarfs near that edge may or may not be bound.")
        sheet.notes.append("Cosmicflows-4 splits the Local Group into Andromeda's group and the Milky Way's, whose leader PGC 5064336 is the Milky Way itself (Kourkchi & Tully 2017), with only Leo I and Leo II measured. It lists the Magellanic Clouds on their own. Atlas draws the whole Local Group from the Local Volume Database instead.")
        guard let group else { return sheet }
        let dwarfs = group.members.filter { $0.id != LocalGroupGalaxy.milkyWayID && $0.id != LocalGroupGalaxy.andromedaID }
        sheet.facts = [
            .init(label: "Galaxies", value: group.members.count.formatted(),
                  detail: group.candidateCount > 0 ? "confirmed; \(group.candidateCount) candidates left out" : "confirmed"),
            .init(label: "Milky Way's side", value: dwarfs.filter { $0.side == .milkyWay }.count.formatted(), detail: "satellites, the LMC's own among them"),
            .init(label: "Andromeda's side", value: dwarfs.filter { $0.side == .andromeda }.count.formatted(), detail: "satellites, Triangulum and its own among them"),
            .init(label: "On their own", value: dwarfs.filter { $0.side == .neither }.count.formatted(), detail: "bound to the group, not to either big galaxy"),
            .init(label: "Width", value: "≈ \(GraphBuilder.lightYearsText(parsecs: radius * 2 * 1000))", detail: "\(GraphBuilder.distanceNumber(radius * 2 / 1000)) Mpc across"),
        ]
        if let mw = group.milkyWay, let m31 = group.andromeda {
            let d = simd_distance(mw.position, m31.position)
            sheet.facts.append(.init(label: "Milky Way to Andromeda", value: "\(d.formatted(.number.precision(.fractionLength(0)))) kpc",
                                     detail: "\(GraphBuilder.lightYearsText(parsecs: d * 1000)), centre to centre"))
            if let v = m31.velocityKmS, v < 0 {
                sheet.facts.append(.init(label: "Andromeda is coming toward us at", value: "\(abs(v).formatted(.number.precision(.fractionLength(0)))) km/s",
                                         detail: "as seen from the Sun; much of it is the Sun's own orbit around the Milky Way"))
            }
        }
        if let nearest = dwarfs.min(by: { ($0.distanceKpc ?? .infinity) < ($1.distanceKpc ?? .infinity) }), let d = nearest.distanceKpc {
            sheet.facts.append(.init(label: "Nearest to us", value: nearest.name, detail: "\(GraphBuilder.lightYearsText(parsecs: d * 1000)) away"))
        }
        if let farthest = group.members.max(by: { ($0.distanceKpc ?? 0) < ($1.distanceKpc ?? 0) }), let d = farthest.distanceKpc {
            sheet.facts.append(.init(label: "Farthest from us", value: farthest.name, detail: "\(GraphBuilder.lightYearsText(parsecs: d * 1000)) away"))
        }
        let heaviest = group.members.filter { $0.logStellarMass != nil }.sorted { $0.logStellarMass! > $1.logStellarMass! }.prefix(6)
        if !heaviest.isEmpty {
            sheet.lists.append(.init(title: "Most stars (after the two big spirals)", items: heaviest.map { "\($0.name) · \(suns(logMass: $0.logStellarMass!))" }))
        }
        return sheet
    }

    static func localGroupGalaxy(_ g: LocalGroupGalaxy, _ group: LocalGroup?, _ boundaries: ConstellationBoundaries?) -> FactSheet {
        let type = GalaxyType(morphology: g.morphology)
        let isDwarf = g.logStellarMass.map { $0 < 9.5 } ?? (g.id != LocalGroupGalaxy.andromedaID)
        let distance = g.distanceKpc.map { " \(GraphBuilder.lightYearsText(parsecs: $0 * 1000)) away" } ?? ""
        var sheet = FactSheet(
            title: g.name,
            summary: "\(noun(type, isDwarf: isDwarf)) \(belonging(g)),\(distance).",
            source: "Local Volume Database (Pace 2025)\(g.distanceSource.map { "; distance from \($0)" } ?? ""). Type: McConnachie (2012)."
        )
        // About three half-light radii across, so the galaxy fills the middle; tiny ones get at least 6′.
        let fov = min(max((g.halfLightArcmin ?? 2) * 6 / 60, 0.1), 8)
        var photo = CelestialPhotos.sky(raDeg: g.raDeg, decDeg: g.decDeg, fovDegrees: fov)
        if let mv = g.absoluteMagnitudeV, mv > -8 {
            photo.caption = "\(photo.caption ?? ""). Too faint to pick out: its few stars only show up when counted"
        }
        sheet.header = .photo(photo)

        if let morphology = g.morphology {
            sheet.facts.append(.init(label: "Type", value: type.map(typeName) ?? morphology, detail: type == nil ? nil : morphology))
        }
        if let d = g.distanceKpc {
            // The error to the same decimal place as the distance, and never shown as zero.
            let digits = d < 100 ? 1 : 0
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits))
            let error = g.distanceErrorKpc.map { " ± \(max($0, pow(10, -Double(digits))).formatted(format))" } ?? ""
            sheet.facts.append(.init(label: "Distance", value: "\(d.formatted(format))\(error) kpc",
                                     detail: GraphBuilder.lightYearsText(parsecs: d * 1000)))
        }
        if let host = g.hostInSentence, let d = g.distanceFromHostKpc {
            sheet.facts.append(.init(label: "From \(host)'s centre",
                                     value: "\(d.formatted(.number.precision(.fractionLength(d < 100 ? 1 : 0)))) kpc", detail: GraphBuilder.lightYearsText(parsecs: d * 1000)))
        }
        if let d = g.distanceFromCentreKpc {
            sheet.facts.append(.init(label: "From the Local Group's centre", value: "\(d.formatted(.number.precision(.fractionLength(0)))) kpc",
                                     detail: GraphBuilder.lightYearsText(parsecs: d * 1000)))
        }
        if let m = g.logStellarMass {
            sheet.facts.append(.init(label: "Mass in stars", value: "≈ \(suns(logMass: m))", detail: "estimated from its light"))
        }
        if let l = g.luminositySuns, let mv = g.absoluteMagnitudeV {
            sheet.facts.append(.init(label: "Shines like", value: "≈ \(compactSuns(l))", detail: "in visible light; absolute magnitude \(mv.formatted(.number.precision(.fractionLength(1))))"))
        }
        if let v = g.velocityKmS { sheet.facts.append(lineOfSight(v)) }
        if let c = constellation(SkyCoordinates.cartesian(longitudeDeg: g.raDeg, latitudeDeg: g.decDeg, distance: 1), boundaries) {
            sheet.facts.append(.init(label: "Constellation", value: c))
        }
        sheet.facts.append(.init(label: "Known planets", value: "None", detail: "none confirmed beyond the Milky Way yet"))
        if g.morphology == nil {
            sheet.notes.append("Not in McConnachie's (2012) list, most likely found since, so no Hubble type is given.")
        }
        if isDwarf { sheet.notes.append("Dwarf galaxies are mostly dark matter: the mass in stars is a small part of the whole.") }
        return sheet
    }

    private static func belonging(_ g: LocalGroupGalaxy) -> String {
        switch (g.hostName, g.side) {
        case ("Milky Way", _): return "orbiting the Milky Way"
        case ("Andromeda Galaxy", _): return "orbiting Andromeda"
        case (_?, .milkyWay): return "orbiting \(g.hostInSentence ?? ""), in the Milky Way's family"
        case (_?, .andromeda): return "orbiting \(g.hostInSentence ?? ""), in Andromeda's family"
        case (nil, .andromeda): return "in the Local Group"
        default: return "in the Local Group, bound to neither big galaxy"
        }
    }

    private static func noun(_ type: GalaxyType?, isDwarf: Bool) -> String {
        switch type {
        case .spiral: return "A spiral galaxy"
        case .lenticular: return "A lenticular galaxy"
        case .elliptical: return isDwarf ? "A dwarf elliptical galaxy" : "An elliptical galaxy"
        case .irregular: return isDwarf ? "A dwarf irregular galaxy" : "An irregular galaxy"
        case .dwarfSpheroidal: return "A dwarf spheroidal galaxy"
        case nil: return isDwarf ? "A dwarf galaxy" : "A galaxy"
        }
    }

    private static func typeName(_ type: GalaxyType) -> String {
        switch type {
        case .spiral: return "Spiral"
        case .lenticular: return "Lenticular"
        case .elliptical: return "Elliptical"
        case .irregular: return "Irregular"
        case .dwarfSpheroidal: return "Dwarf spheroidal"
        }
    }

    /// "2.9 billion Suns" from log10 of a mass in Suns.
    private static func suns(logMass: Double) -> String { compactSuns(pow(10, logMass)) }

    private static func compactSuns(_ value: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(2))
        switch value {
        case 1e9...: return "\((value / 1e9).formatted(format)) billion Suns"
        case 1e6...: return "\((value / 1e6).formatted(format)) million Suns"
        default: return "\(value.formatted(format)) Suns"
        }
    }
}
