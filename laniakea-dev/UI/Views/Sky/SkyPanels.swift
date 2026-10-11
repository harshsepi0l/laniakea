import simd
import SwiftUI

/// The live corner map: where the picked object lives in Atlas, with a wedge showing which way
/// you're facing. Stars show on a map of the stars around the Sun; planets and the Sun on the
/// Solar System. Updates as you move.
struct SkyCornerMap: View {
    @ObservedObject var model: SkyViewModel
    let selected: SkyObject?
    let projection: () -> SkyProjection

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            Canvas { context, size in draw(in: &context, size: size, date: timeline.date) }
        }
        .frame(width: 150, height: 150)
        .background(Color(red: 0.043, green: 0.047, blue: 0.063).opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12)))
        .overlay(alignment: .topLeading) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(white: 0.8)).padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Tap to open").font(.system(size: 10)).foregroundColor(Color(white: 0.5)).padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var isSolarSystem: Bool {
        switch selected?.kind {
        case .planet, .sun: return true
        default: return false
        }
    }

    private var title: String { isSolarSystem ? "Solar System" : "Milky Way" }
    private var here: Color { Color(red: 1.0, green: 0.69, blue: 0.36) }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        if isSolarSystem { drawSolarSystem(in: &context, size: size, date: date) } else { drawStars(in: &context, size: size, date: date) }
    }

    /// Naked-eye stars seen from above the Milky Way's disc, the Sun at the centre, scaled so the
    /// picked star sits near the edge.
    private func drawStars(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
        var target: (point: SIMD2<Double>, distance: Double)?
        if case .star(let star, _) = selected?.kind, let p = star.position, let d = star.distanceParsecs {
            target = (SIMD2(p.x, p.y), d)
        }
        let reach = max((target?.distance ?? 100) * 1.4, 20)
        let scale = Double(size.width) * 0.42 / reach
        func screen(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: centre.x + p.x * scale, y: centre.y - p.y * scale) }

        // Zoomed out, thousands of stars fall inside the map, so they shrink and fade to stay a backdrop.
        let dot: CGFloat = reach > 120 ? 1.1 : 2
        let opacity = reach > 120 ? 0.3 : 0.55
        var bins: [Int: Path] = [:]
        for star in model.nakedEye {
            guard let p = star.position, abs(p.x) < reach * 1.3, abs(p.y) < reach * 1.3 else { continue }
            let s = screen(SIMD2(p.x, p.y))
            bins[StarColor.bin(temperature: star.temperatureK ?? 5772), default: Path()].addEllipse(in: CGRect(x: s.x - dot / 2, y: s.y - dot / 2, width: dot, height: dot))
        }
        for (bin, path) in bins { context.fill(path, with: .color(StarColor.color(bin: bin).color(dark: true).opacity(opacity))) }

        drawWedge(in: &context, centre: centre, radius: size.width * 0.75, date: date)

        if let target {
            let p = screen(target.point)
            var line = Path(); line.move(to: centre); line.addLine(to: p)
            context.stroke(line, with: .color(here), lineWidth: 1.4)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(here), lineWidth: 1.6)
            if let selected {
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(StarColor.swiftUI(temperature: selected.temperatureK, dark: true)))
            }
        }
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12)), with: .color(here), lineWidth: 2)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)), with: .color(StarColor.swiftUI(temperature: 5772, dark: true)))
    }

    /// The direction you're facing, flattened onto the Milky Way's disc, as a shaded wedge.
    private func drawWedge(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat, date: Date) {
        guard let sky = model.localSky(at: date) else { return }
        let proj = projection()
        let eq = SkyCoordinates.spherical(sky.equatorialJ2000(ofDirection: proj.look))
        let g = SkyCoordinates.galactic(raDeg: eq.l, decDeg: eq.b)
        let angle = g.l * .pi / 180, half = proj.widthDegrees / 2 * .pi / 180
        var wedge = Path()
        wedge.move(to: centre)
        for k in 0...12 {
            let a = angle - half + 2 * half * Double(k) / 12
            wedge.addLine(to: CGPoint(x: centre.x + CGFloat(cos(a)) * radius, y: centre.y - CGFloat(sin(a)) * radius))
        }
        wedge.closeSubpath()
        context.fill(wedge, with: .color(here.opacity(0.13)))
    }

    /// The Solar System today, orbits evenly spaced as in Atlas, with your line of sight from Earth.
    private func drawSolarSystem(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let planets = model.planets
        guard !planets.isEmpty else { return }
        let space = SceneSpace(semiMajorAxesAU: planets.map(\.orbit.semiMajorAxisAU))
        let centre = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
        let scale = Double(size.width) * 0.4 / space.outerRadius
        func screen(_ planet: Planet) -> CGPoint {
            let p = space.position(planet.orbit.position(at: date))
            return CGPoint(x: centre.x + p.x * scale, y: centre.y - p.y * scale)
        }
        for planet in planets {
            let r = space.distance(au: planet.orbit.semiMajorAxisAU) * scale
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.07)))
        }
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8)), with: .color(StarColor.swiftUI(temperature: 5772, dark: true)))
        let earth = planets.first { $0.id == Planet.earthID }.map(screen)
        var target: CGPoint?
        if case .planet(let picked) = selected?.kind { target = screen(picked) }
        if case .sun = selected?.kind { target = centre }
        if let earth, let target {
            var line = Path(); line.move(to: earth); line.addLine(to: target)
            context.stroke(line, with: .color(here), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
            context.stroke(Path(ellipseIn: CGRect(x: target.x - 7, y: target.y - 7, width: 14, height: 14)), with: .color(here), lineWidth: 1.6)
        }
        for planet in planets {
            let p = screen(planet)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(planet.composition.swiftUI(dark: true)))
        }
        if let earth {
            context.stroke(Path(ellipseIn: CGRect(x: earth.x - 5, y: earth.y - 5, width: 10, height: 10)), with: .color(here), lineWidth: 1.6)
        }
    }
}

/// The facts panel at the bottom: what's in the crosshair, its key facts, where it lives in Atlas,
/// and buttons for the full fact sheet and for Atlas.
struct SkyFactsPanel: View {
    @ObservedObject var model: SkyViewModel
    let object: SkyObject?
    let onFacts: () -> Void
    let onOpenInAtlas: () -> Void
    /// Opens a constellation's fact sheet, by IAU abbreviation.
    let onConstellation: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let object {
                header(object)
                let facts = facts(for: object)
                if !facts.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(facts) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.label).font(.system(size: 11)).foregroundColor(Color(white: 0.6))
                                Text(fact.value).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
                        }
                    }
                }
                if case .star(_, let host?) = object.kind {
                    Button(action: onFacts) {
                        HStack(spacing: 8) {
                            Circle().fill(PlanetComposition.gasRich.swiftUI(dark: true)).frame(width: 8, height: 8)
                            Text(host.planetCount == 1 ? "1 known planet" : "\(host.planetCount) known planets").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12))
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                if case .sun = object.kind {
                    Text("Never look at the Sun through a camera or binoculars.")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Color(red: 1, green: 0.69, blue: 0.36))
                }
                ladder(object)
                HStack(spacing: 10) {
                    Button(action: onFacts) {
                        Text("Facts").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    Button(action: onOpenInAtlas) {
                        Text("Open in Atlas").font(.system(size: 16, weight: .semibold)).foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color(red: 1, green: 0.69, blue: 0.36), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Point the crosshair at a star or planet.").font(.system(size: 14)).foregroundColor(Color(white: 0.75))
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .background(Color(white: 0.11).opacity(0.94), in: RoundedRectangle(cornerRadius: 26))
        .animation(.easeInOut(duration: 0.2), value: object?.id)
    }

    private func header(_ object: SkyObject) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color(object)).frame(width: 14, height: 14).shadow(color: color(object).opacity(0.8), radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(object.name).font(.system(size: 22, weight: .bold))
                HStack(spacing: 4) {
                    if let designation = designation(object) {
                        Text(designation).foregroundColor(Color(white: 0.65))
                    }
                    if let abbreviation = model.boundaries?.constellation(of: object.equatorial) {
                        // The constellation opens its own fact sheet.
                        Button { onConstellation(abbreviation) } label: {
                            Text("in \(Constellation.name(abbreviation))").underline()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 1, green: 0.69, blue: 0.36))
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
            }
        }
    }

    private func color(_ object: SkyObject) -> Color {
        if case .planet = object.kind { return object.composition.swiftUI(dark: true) }
        return StarColor.swiftUI(temperature: object.temperatureK, dark: true)
    }

    /// What comes before the constellation in the subtitle: "α Lyrae ·", "Planet ·" or "Our star ·".
    private func designation(_ object: SkyObject) -> String? {
        switch object.kind {
        case .star(let star, _): return star.properName != nil ? star.designation.map { "\($0) ·" } : nil
        case .planet: return "Planet ·"
        case .sun: return "Our star ·"
        }
    }

    private func facts(for object: SkyObject) -> [FactSheet.Fact] {
        switch object.kind {
        case .star(let star, _):
            let sheet = FactSheetBuilder.nakedEyeStar(star, model.boundaries)
            let wanted = ["Distance", "Surface temperature", "Width", "Shines like", "Spectral type", "From Earth"]
            return Array(wanted.compactMap { label in sheet.facts.first { $0.label == label } }.prefix(4))
        case .planet(let planet):
            var facts: [FactSheet.Fact] = []
            if let au = distanceFromEarth(planet) {
                facts.append(.init(label: "From Earth now", value: "\(au.formatted(.number.precision(.fractionLength(2)))) au"))
            }
            if let makeup = planet.composition { facts.append(.init(label: "Makeup", value: makeup.name)) }
            if let r = planet.meanRadiusKm { facts.append(.init(label: "Diameter", value: "\((r * 2).formatted(.number.precision(.fractionLength(0)))) km")) }
            let years = planet.orbit.periodDays / 365.25
            facts.append(.init(label: "Length of year", value: years < 2 ? "\(planet.orbit.periodDays.formatted(.number.precision(.fractionLength(0)))) days" : "\(years.formatted(.number.precision(.fractionLength(1)))) years"))
            return facts
        case .sun:
            guard let earth = model.planets.first(where: { $0.id == Planet.earthID }) else { return [] }
            let au = simd_length(earth.orbit.position(at: Date()))
            return [.init(label: "From Earth now", value: "\(au.formatted(.number.precision(.fractionLength(3)))) au")]
        }
    }

    private func distanceFromEarth(_ planet: Planet) -> Double? {
        guard let earth = model.planets.first(where: { $0.id == Planet.earthID }) else { return nil }
        return simd_length(planet.orbit.position(at: Date()) - earth.orbit.position(at: Date()))
    }

    /// Where it lives, from the outside in.
    private func ladder(_ object: SkyObject) -> some View {
        let steps: [String]
        switch object.kind {
        case .star(_, let host?): steps = ["Laniakea", "Milky Way", object.name, host.planetCount == 1 ? "1 planet" : "\(host.planetCount) planets"]
        case .star: steps = ["Laniakea", "Milky Way", object.name]
        case .planet, .sun: steps = ["Milky Way", "Solar System", object.name]
        }
        return HStack(spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 { Text("›").foregroundColor(Color(white: 0.45)) }
                Text(step).foregroundColor(step == object.name ? Color(red: 1, green: 0.69, blue: 0.36) : Color(white: 0.6))
                    .fontWeight(step == object.name ? .semibold : .regular)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}
