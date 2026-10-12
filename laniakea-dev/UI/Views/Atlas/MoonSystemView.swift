import simd
import SwiftUI

/// A planet's moons on its card: their orbits drawn to scale around the planet as they are today,
/// then every moon Horizons knows by name. Tap one for its facts.
struct MoonSystemSection: View {
    let planet: Planet
    @ObservedObject var moons: MoonsViewModel

    @State private var showsInner = false
    @State private var picked: Moon?
    @State private var loadingID: String?

    var body: some View {
        let drawn = moons.moons(of: planet.id)
        let listing = moons.listing(of: planet.id)
        VStack(alignment: .leading, spacing: 10) {
            if !drawn.isEmpty || !listing.isEmpty || moons.loadingPrimaries.contains(planet.id) {
                Text(listing.isEmpty ? "Moons" : listing.count == 1 ? "1 known moon" : "\(listing.count) known moons")
                    .font(.system(size: 20, weight: .bold))
            }
            if !drawn.isEmpty {
                MoonOrbitsView(planet: planet, moons: drawn, showsInner: showsInner)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(alignment: .top) {
                    Text("To scale, seen from above the plane of Earth's orbit, today."
                         + (planet.id == "799" ? " Uranus is tipped on its side, so its moons' orbits look nearly edge-on from there." : "")
                         + " Lines are orbits; dots are where the moons are now.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if canZoom(drawn) {
                        Spacer(minLength: 8)
                        Button(showsInner ? "All" : "Inner moons") { withAnimation { showsInner.toggle() } }
                            .font(.system(size: 13, weight: .semibold)).tint(.orange)
                    }
                }
            }
            if moons.loadingPrimaries.contains(planet.id) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading moons from NASA JPL Horizons…").font(.system(size: 13)).foregroundColor(.secondary)
                }
            }
            if let error = moons.errors[planet.id] {
                Text(error).font(.system(size: 13)).foregroundColor(.secondary)
            }
            if !listing.isEmpty { list(listing) }
        }
        .onAppear { moons.load(primaryID: planet.id) }
        .sheet(item: $picked) { MoonDetailSheet(moon: $0, primaryName: planet.name) }
    }

    /// Worth zooming when the outer moons squeeze the inner ones into the planet.
    private func canZoom(_ drawn: [Moon]) -> Bool {
        let axes = drawn.map(\.orbit.semiMajorAxisAU).sorted()
        guard let first = axes.first, let last = axes.last else { return false }
        return last / first > 8
    }

    private func list(_ listing: [MoonListing]) -> some View {
        let drawnIDs = Set(MoonsViewModel.drawn[planet.id] ?? [])
        let main = listing.filter { drawnIDs.contains($0.id) }
        let rest = listing.filter { !drawnIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(main) { row($0) }
            if !rest.isEmpty {
                DisclosureGroup {
                    ForEach(rest) { row($0) }
                } label: {
                    Text(main.isEmpty ? "All \(rest.count)" : "\(rest.count) smaller moons")
                        .font(.system(size: 15, weight: .semibold))
                }
                .tint(.orange)
                .padding(.vertical, 6)
            }
        }
    }

    private func row(_ listing: MoonListing) -> some View {
        Button {
            Task {
                loadingID = listing.id
                picked = await moons.moon(id: listing.id)
                loadingID = nil
            }
        } label: {
            HStack {
                Text(listing.name).font(.system(size: 15))
                Spacer()
                if loadingID == listing.id {
                    ProgressView()
                } else if let r = moons.loaded[listing.id]?.meanRadiusKm {
                    Text("\((r * 2).formatted(.number.precision(.fractionLength(0)))) km wide")
                        .font(.system(size: 13)).foregroundColor(.secondary).monospacedDigit()
                }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.secondary)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Orbits around a planet, drawn to one scale with the planet itself, seen from ecliptic north.
private struct MoonOrbitsView: View {
    let planet: Planet
    let moons: [Moon]
    let showsInner: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .background(Color(red: 0.016, green: 0.024, blue: 0.043))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let now = Date()
        let paths: [(moon: Moon, points: [SIMD2<Double>], now: SIMD2<Double>)] = moons.map { moon in
            let steps = 96
            let points = (0...steps).map { k -> SIMD2<Double> in
                let p = moon.orbit.position(at: now.addingTimeInterval(moon.orbit.periodDays * 86400 * Double(k) / Double(steps)))
                return SIMD2(p.x, p.y) * Moon.kmPerAU
            }
            let p = moon.orbit.position(at: now)
            return (moon, points, SIMD2(p.x, p.y) * Moon.kmPerAU)
        }
        // Fit the outermost orbit, or with "inner moons" the middle one.
        let reaches = paths.map { $0.points.map { simd_length($0) }.max() ?? 0 }.sorted()
        guard var reach = reaches.last, reach > 0 else { return }
        if showsInner, reaches.count > 1 { reach = reaches[(reaches.count - 1) / 2] }
        let scale = Double(min(size.width, size.height)) / 2 * 0.86 / reach
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func screen(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: centre.x + p.x * scale, y: centre.y - p.y * scale) }

        for item in paths {
            var line = Path()
            for (i, p) in item.points.enumerated() {
                if i == 0 { line.move(to: screen(p)) } else { line.addLine(to: screen(p)) }
            }
            context.stroke(line, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
        // The planet at its true size; a hairline ring marks it when it's smaller than a dot.
        let r = CGFloat((planet.meanRadiusKm ?? 0) * scale)
        let color = planet.composition.swiftUI(dark: true)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)), with: .color(color))
        if r < 3 {
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)), with: .color(color), lineWidth: 1)
        }
        var taken: [CGRect] = [CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)]
        let bounds = CGRect(origin: .zero, size: size)
        for item in paths {
            let p = screen(item.now)
            guard bounds.insetBy(dx: -10, dy: -10).contains(p) else { continue }
            let dot = max(2.5, CGFloat((item.moon.meanRadiusKm ?? 0) * scale))
            context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(Color(white: 0.85)))
            let label = context.resolve(Text(item.moon.name).font(.system(size: 11)).foregroundColor(Color(white: 0.75)))
            let s = label.measure(in: size)
            let candidates = [
                CGRect(x: p.x + dot + 4, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - dot - 4 - s.width, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y - dot - 2 - s.height, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y + dot + 2, width: s.width, height: s.height),
            ]
            if let rect = candidates.first(where: { bounds.contains($0) && !taken.contains(where: $0.intersects) }) {
                taken.append(rect)
                context.draw(label, in: rect)
            }
        }
        drawScaleBar(in: &context, size: size, kmPerPoint: 1 / scale)
    }

    /// A round number of km about a fifth of the width.
    private func drawScaleBar(in context: inout GraphicsContext, size: CGSize, kmPerPoint: Double) {
        let target = Double(size.width) * 0.2 * kmPerPoint
        let power = pow(10, floor(log10(target)))
        let km = [1.0, 2, 5, 10].map { $0 * power }.last { $0 <= target } ?? power
        let length = CGFloat(km / kmPerPoint)
        let y = size.height - 16, x = CGFloat(14)
        var bar = Path()
        bar.move(to: CGPoint(x: x, y: y - 3)); bar.addLine(to: CGPoint(x: x, y: y))
        bar.addLine(to: CGPoint(x: x + length, y: y)); bar.addLine(to: CGPoint(x: x + length, y: y - 3))
        context.stroke(bar, with: .color(.white.opacity(0.6)), lineWidth: 1)
        let text = context.resolve(Text("\(km.formatted(.number.precision(.fractionLength(0)))) km").font(.system(size: 10)).foregroundColor(.white.opacity(0.7)))
        context.draw(text, at: CGPoint(x: x + length + 6, y: y - 2), anchor: .leading)
    }
}

/// One moon's card: its size beside our Moon, its orbit and Horizons' physical data.
struct MoonDetailSheet: View {
    let moon: Moon
    let primaryName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let r = moon.meanRadiusKm {
                    FactHeaderView(header: .toScale(
                        [.init(name: moon.name, radius: r, look: .planet(PlanetComposition.solarSystem(densityGramsPerCm3: moon.densityGramsPerCm3)))]
                            + (moon.id == "301" ? [.init(name: "Earth", radius: 6371, look: .planet(.rocky))]
                               : [.init(name: "The Moon", radius: 1737.4, look: .planet(.rocky))])
                    ))
                }
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(moon.name).font(.system(size: 30, weight: .bold))
                        Text(summary).font(.system(size: 16)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    FactGrid(facts: facts)
                    Text("Source: NASA JPL Horizons (body \(moon.id)). Its orbit is today's, around \(primaryName)'s centre.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(20)
            }
        }
        .factSheetPresentation()
    }

    private var summary: String {
        let km = moon.orbit.semiMajorAxisAU * Moon.kmPerAU
        return "Orbits \(primaryName) every \(Self.duration(days: moon.orbit.periodDays)), "
            + "at an average distance of \(km.formatted(.number.precision(.fractionLength(0)))) km."
    }

    private var facts: [FactSheet.Fact] {
        var facts: [FactSheet.Fact] = []
        if let r = moon.meanRadiusKm {
            let shape = moon.triaxialRadiiKm.map { axes in
                "Not round: " + axes.map { ($0 * 2).formatted(.number.precision(.fractionLength(axes.allSatisfy { $0 >= 100 } ? 0 : 1))) }.joined(separator: " × ") + " km"
            }
            facts.append(.init(label: "Diameter", value: "\(moon.triaxialRadiiKm == nil ? "" : "≈ ")\((r * 2).formatted(.number.precision(.fractionLength(r < 50 ? 1 : 0)))) km", detail: shape))
        }
        if let m = moon.massKg { facts.append(.init(label: "Mass", value: Self.scientific(m, unit: "kg"))) }
        if let d = moon.densityGramsPerCm3 { facts.append(.init(label: "Density", value: "\(d.formatted(.number.precision(.fractionLength(2)))) g/cm³")) }
        facts.append(.init(label: "From \(primaryName) now", value: "\(moon.distanceKm(at: Date()).formatted(.number.precision(.fractionLength(0)))) km"))
        if moon.isSynchronous { facts.append(.init(label: "Spin", value: "Keeps one face to \(primaryName)")) }
        if let a = moon.geometricAlbedo { facts.append(.init(label: "Reflects", value: "\((a * 100).formatted(.number.precision(.fractionLength(0))))% of sunlight", detail: "Geometric albedo")) }
        facts.append(.init(label: "Orbit shape", value: "Eccentricity \(moon.orbit.eccentricity.formatted(.number.precision(.fractionLength(3))))"))
        return facts
    }

    static func duration(days: Double) -> String {
        days < 2 ? "\((days * 24).formatted(.number.precision(.fractionLength(1)))) hours"
            : days < 1000 ? "\(days.formatted(.number.precision(.fractionLength(days < 10 ? 2 : 1)))) days"
            : "\((days / 365.25).formatted(.number.precision(.fractionLength(1)))) years"
    }

    /// e.g. 8.93 × 10²² kg
    static func scientific(_ value: Double, unit: String) -> String {
        let exponent = Int(floor(log10(value)))
        let mantissa = value / pow(10, Double(exponent))
        let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return "\(mantissa.formatted(.number.precision(.fractionLength(2)))) × 10\(String(String(exponent).compactMap { superscripts[$0] })) \(unit)"
    }
}
