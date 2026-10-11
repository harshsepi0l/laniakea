import SwiftUI

/// Another star's planets on their orbits, seen from above. A planet's place along its orbit is known
/// only when a time it passed between its star and Earth has been measured (a transit, or a conjunction
/// from radial velocities), so only those are drawn as moving dots; the others show as dashed orbits.
/// Earth is toward the bottom of the screen. The star takes its color from its temperature.
struct ExoplanetSystemView: View {
    let system: StarSystem
    let planets: [Exoplanet]
    @ObservedObject var clock: SimulationClock

    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: Exoplanet?
    @State private var showPlanets = false

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: !clock.isPlaying)) { timeline in
                let _ = clock.tick(now: timeline.date)
                Canvas { context, size in draw(in: &context, size: size) }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                selected = planet(at: value.location, size: geo.size)
            })
        }
        .overlay(alignment: .bottomLeading) {
            if !planets.isEmpty, planets.allSatisfy({ phase(of: $0) == nil }) {
                note("Where these planets are along their orbits hasn't been measured.")
                    .padding(16)
            }
        }
        // A pull-out list, like the other maps' objects panels, so it never covers the system.
        .overlay(alignment: .topTrailing) {
            planetPanel
                .padding(.top, 64)
                .padding(.bottom, 8)
        }
        .sheet(item: $selected) { planet in
            ExoplanetDetailSheet(planet: planet, system: system)
        }
    }

    private var planetPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            if !showPlanets {
                Button {
                    showPlanets = true
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6), in: Circle())
                }
                .accessibilityLabel("Show planets")
                .padding(.trailing, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(planets.count == 1 ? "1 planet" : "\(planets.count) planets")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showPlanets = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Hide planets")
                    }
                    .padding(.leading, 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(planets) { planet in
                                Button { selected = planet } label: {
                                    HStack(spacing: 10) {
                                        let color = planet.composition.swiftUI(dark: colorScheme == .dark)
                                        Circle()
                                            .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: phase(of: planet) == nil ? [2, 2] : []))
                                            .background(Circle().fill(phase(of: planet) == nil ? Color.clear : color))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(planet.name).font(.system(size: 14)).lineLimit(1)
                                            if let a = planet.semiMajorAxisAU {
                                                Text("\(a.formatted(.number.precision(.significantDigits(2)))) au")
                                                    .font(.system(size: 11).monospacedDigit())
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                        .fill(Color(.systemGray6))
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPlanets)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Layout

    /// Orbits are spaced evenly by rank so close-in planets stay visible; the real sizes are listed.
    private func orbitRadius(_ index: Int, size: CGSize) -> CGFloat {
        let outer = min(systemWidth(size), size.height) / 2 * 0.82
        // Room inside the first orbit for the star and its name.
        let inner = outer * 0.36
        guard planets.count > 1 else { return (inner + outer) / 2 }
        return inner + (outer - inner) * CGFloat(index) / CGFloat(planets.count - 1)
    }

    /// Orbital phase (0…1, 0 when between the star and Earth) at the clock's time, if known.
    private func phase(of planet: Exoplanet) -> Double? {
        guard let t0 = planet.transitMidpointJD, let period = planet.periodDays, period > 0 else { return nil }
        let now = OrbitalElements.julianDay(clock.simulatedDate)
        let cycles = (now - t0) / period
        return cycles - floor(cycles)
    }

    /// Width left for the system: on a narrow screen it moves aside while the planet panel is open.
    private func systemWidth(_ size: CGSize) -> CGFloat {
        showPlanets && size.width < 600 ? size.width - Self.panelWidth : size.width
    }

    private func centre(_ size: CGSize) -> CGPoint {
        CGPoint(x: systemWidth(size) / 2, y: size.height * 0.52)
    }

    private static let panelWidth: CGFloat = 190

    private func position(_ index: Int, size: CGSize) -> CGPoint? {
        guard let phase = phase(of: planets[index]) else { return nil }
        let centre = centre(size)
        let r = orbitRadius(index, size: size)
        // At transit the planet is between the star and Earth: straight down on screen.
        let angle = Double.pi / 2 + phase * 2 * .pi
        return CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle)))
    }

    private func planet(at point: CGPoint, size: CGSize) -> Exoplanet? {
        planets.indices.compactMap { i -> (Int, CGFloat)? in
            guard let p = position(i, size: size) else { return nil }
            return (i, hypot(p.x - point.x, p.y - point.y))
        }
        .filter { $0.1 < 30 }
        .min { $0.1 < $1.1 }
        .map { planets[$0.0] }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let dark = colorScheme == .dark
        let ink: Color = dark ? .white : Color(white: 0.07)
        let star = StarColor.swiftUI(temperature: system.temperatureK, dark: dark)
        let centre = centre(size)

        let glow: CGFloat = 46
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(Gradient(colors: [star.opacity(0.5), star.opacity(0)]), center: centre, startRadius: 0, endRadius: glow)
        )
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 7, y: centre.y - 7, width: 14, height: 14)), with: .color(star))

        for i in planets.indices {
            let r = orbitRadius(i, size: size)
            let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            let known = phase(of: planets[i]) != nil
            context.stroke(ring, with: .color(ink.opacity(known ? 0.14 : 0.22)),
                           style: StrokeStyle(lineWidth: 1, dash: known ? [] : [3, 4]))
            guard let p = position(i, size: size) else { continue }
            let dot = 2.4 + 2.6 * CGFloat(min((planets[i].radiusEarths ?? 1) / 11, 1).squareRoot())
            let color = planets[i].composition.swiftUI(dark: dark)
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - dot * 3, y: p.y - dot * 3, width: dot * 6, height: dot * 6)),
                with: .radialGradient(Gradient(colors: [color.opacity(dark ? 0.3 : 0.18), color.opacity(0)]), center: p, startRadius: 0, endRadius: dot * 3)
            )
            context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(color))
        }

        let label = context.resolve(Text(system.name).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary))
        let labelSize = label.measure(in: size)
        let labelRect = CGRect(x: centre.x - labelSize.width / 2, y: centre.y - 22 - labelSize.height / 2,
                               width: labelSize.width, height: labelSize.height)
        context.fill(Path(roundedRect: labelRect.insetBy(dx: -4, dy: -1), cornerRadius: 4), with: .color(Color(.systemBackground).opacity(0.78)))
        context.draw(label, in: labelRect)
        let earth = context.resolve(Text("↓ toward Earth").font(.system(size: 10.5)).foregroundColor(.secondary))
        context.draw(earth, at: CGPoint(x: centre.x, y: centre.y + orbitRadius(max(planets.count - 1, 0), size: size) + 16))
    }
}

struct ExoplanetDetailSheet: View {
    let planet: Exoplanet
    let system: StarSystem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if let makeup = planet.composition {
                            let color = makeup.swiftUI(dark: colorScheme == .dark)
                            Circle().fill(color).frame(width: 16, height: 16).shadow(color: color.opacity(0.7), radius: 6)
                        }
                        Text(planet.name).font(.system(size: 30, weight: .bold))
                    }
                    Text(summary).font(.system(size: 16)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FactGrid(facts: facts)
                if planet.equilibriumTempK != nil {
                    Text("Temperature assumes no atmosphere to trap heat, as the archive calculates it.")
                        .font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Source: NASA Exoplanet Archive").font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(20)
        }
        .factSheetPresentation()
    }

    private var facts: [FactSheet.Fact] {
        var facts: [FactSheet.Fact] = []
        let number = { (x: Double, digits: Int) in x.formatted(.number.precision(.significantDigits(digits))) }
        if let r = planet.radiusEarths {
            let size = ObjectKind.planet(radiusEarths: r).label
            facts.append(.init(label: "Size", value: "\(planet.radiusIsEstimate == true ? "≈ " : "")\(number(r, 3)) × Earth",
                               detail: planet.radiusIsEstimate == true ? "\(size), estimated from mass" : size))
        }
        if let m = planet.massEarths {
            facts.append(.init(label: "Mass", value: "\(planet.massIsEstimate == true ? "≈ " : planet.massIsMinimum == true ? "≥ " : "")\(number(m, 3)) × Earth",
                               detail: planet.massIsEstimate == true ? "estimated from size" : planet.massIsMinimum == true ? "a minimum; the orbit's tilt is unknown" : nil))
        }
        if let makeup = planet.makeup {
            facts.append(.init(label: "Makeup", value: makeup.composition.name, detail: makeup.evidence.explanation(for: makeup.composition)))
        }
        if let density = planet.densityGramsPerCm3 {
            facts.append(.init(label: "Density", value: "\(density.formatted(.number.precision(.fractionLength(1)))) g/cm³", detail: "Earth is 5.5"))
        }
        if let p = planet.periodDays { facts.append(.init(label: "Length of year", value: "\(number(p, 3)) days")) }
        if let a = planet.semiMajorAxisAU { facts.append(.init(label: "Distance from star", value: "\(number(a, 3)) au")) }
        if let e = planet.eccentricity { facts.append(.init(label: "Eccentricity", value: e.formatted(.number.precision(.fractionLength(2))))) }
        if let t = planet.equilibriumTempK {
            facts.append(.init(label: "Temperature", value: "\((t - 273.15).formatted(.number.precision(.fractionLength(0)))) °C",
                               detail: "from its star's heat alone"))
        }
        if let s = planet.insolationEarths { facts.append(.init(label: "Starlight", value: "\(number(s, s < 10 ? 2 : 3)) × Earth's")) }
        if let year = planet.discoveryYear { facts.append(.init(label: "Discovered", value: String(year))) }
        return facts
    }

    private var summary: String {
        var parts = ["Orbits \(system.name), \(GraphBuilder.lightYearsText(parsecs: system.distanceParsecs)) away."]
        if let method = planet.discoveryMethod, !method.isEmpty { parts.append("Found by \(method.lowercased()).") }
        return parts.joined(separator: " ")
    }

}
