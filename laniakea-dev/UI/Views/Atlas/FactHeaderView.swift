import SwiftUI

/// The picture at the top of a fact sheet: a real photo with its credit, or spheres drawn to their
/// true relative sizes from measurements. Always on black, like space.
struct FactHeaderView: View {
    let header: FactHeader
    var height: CGFloat = 260

    /// The photo that couldn't load; only that address falls back, so a new one retries.
    @State private var failedURL: URL?

    var body: some View {
        switch header {
        case .photo(let photo):
            if failedURL != photo.url {
                photoView(photo)
            } else if let fallback = photo.fallback {
                // Type-erased: a header can fall back to another header.
                AnyView(FactHeaderView(header: fallback, height: height))
            }
        case .toScale(let bodies):
            ToScaleView(bodies: bodies).frame(height: height)
        case .galaxyModel(let model):
            GalaxyModelView(model: model).frame(height: height)
        case .skyChart(let chart):
            SkyChartView(chart: chart, drawsStars: true)
                .frame(height: height)
                .background(Color(red: 0.02, green: 0.024, blue: 0.03))
                .overlay(alignment: .topLeading) { pill("Drawn from the star catalog") }
        }
    }

    private func photoView(_ photo: FactHeader.Photo) -> some View {
        AsyncImage(url: photo.url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                // Sized to the frame (never the other way round), so a wide image can't widen the sheet.
                GeometryReader { geo in
                    if photo.showsLeftHalf {
                        // A little over twice the width, so the strip between the two views falls off the edge.
                        image.resizable().aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width * 2.15)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    } else {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .clipped()
                .overlay {
                    if let overlay = photo.overlay { SkyChartView(chart: overlay, drawsStars: false) }
                }
            case .failure(let error):
                // A load cancelled because the address changed isn't a failure.
                if (error as? URLError)?.code == .cancelled {
                    ProgressView().tint(.white)
                } else {
                    Color.clear.onAppear { failedURL = photo.url }
                }
            default:
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)
        .clipped()
        .overlay(alignment: .topLeading) { pill("Real photo") }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom) {
                if let caption = photo.caption { Text(caption) }
                Spacer(minLength: 12)
                Text(photo.credit).multilineTextAlignment(.trailing)
            }
            .font(.system(size: 10))
            .foregroundColor(Color(white: 0.78))
            .shadow(color: .black, radius: 2)
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo. \(photo.caption ?? ""). Credit \(photo.credit)")
    }
}

/// A sky chart laid over a photo made with the same projection (outline and names only), or drawn
/// on its own with every star. Fills its frame the way the photo does, cropping the same edges.
private struct SkyChartView: View {
    let chart: FactHeader.SkyChart
    let drawsStars: Bool

    var body: some View {
        Canvas { context, size in
            // The photo is width 1, height `aspect`, scaled to fill and centerd.
            let imageWidth = max(size.width, size.height / CGFloat(chart.aspect))
            let imageHeight = imageWidth * CGFloat(chart.aspect)
            let origin = CGPoint(x: (size.width - imageWidth) / 2, y: (size.height - imageHeight) / 2)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: origin.x + imageWidth * (0.5 + CGFloat(x)), y: origin.y + imageHeight / 2 - CGFloat(y) * imageWidth)
            }
            let orange = Color(red: 1, green: 0.69, blue: 0.36)
            var outline = Path()
            for s in chart.outline {
                outline.move(to: point(s.x1, s.y1))
                outline.addLine(to: point(s.x2, s.y2))
            }
            var glow = context
            glow.addFilter(.blur(radius: 3))
            glow.stroke(outline, with: .color(orange.opacity(0.5)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(outline, with: .color(orange.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            if drawsStars {
                for star in chart.stars {
                    let p = point(star.x, star.y)
                    let r = CGFloat(min(max(3.2 - 0.48 * star.magnitude, 0.6), 4.5))
                    let color = StarColor.swiftUI(temperature: star.temperatureK, dark: true)
                    if star.magnitude < 2.5 {
                        context.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                                     with: .radialGradient(Gradient(colors: [color.opacity(0.4), color.opacity(0)]), center: p, startRadius: 0, endRadius: r * 3))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
                }
            }
            for star in chart.stars {
                guard let label = star.label else { continue }
                let p = point(star.x, star.y)
                let text = context.resolve(Text(label).font(.system(size: 10.5)).foregroundColor(Color(white: 0.9)))
                let s = text.measure(in: size)
                let rect = CGRect(x: p.x + 7, y: p.y - s.height / 2, width: s.width, height: s.height)
                guard CGRect(origin: .zero, size: size).contains(rect) else { continue }
                context.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -1), cornerRadius: 3), with: .color(.black.opacity(0.55)))
                context.draw(text, in: rect)
            }
        }
        .allowsHitTesting(false)
    }
}

private func pill(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundColor(Color(white: 0.8))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(white: 0.11).opacity(0.85), in: Capsule())
        .padding(12)
}

/// Spheres side by side at their true relative sizes: stars glow with limb darkening (their edges
/// look dimmer, as real stars' do), planets are lit from one side. A body too small to see at this
/// scale is drawn as a dot and says so.
private struct ToScaleView: View {
    let bodies: [FactHeader.ScaleBody]

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .background(Color(red: 0.02, green: 0.024, blue: 0.03))
            .overlay(alignment: .topLeading) { pill("Drawn from measurements") }
            .overlay(alignment: .bottomLeading) {
                if bodies.contains(where: \.isEstimate) {
                    Text("Dashed edge: size estimated, not measured")
                        .font(.system(size: 10)).foregroundColor(Color(white: 0.65)).padding(10)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let largest = bodies.map(\.radius).max(), largest > 0 else { return "" }
        return "Drawn to scale: " + bodies.map { "\($0.name), \(($0.radius / largest * 100).formatted(.number.precision(.significantDigits(2))))% of the largest" }.joined(separator: "; ")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let largest = bodies.map(\.radius).max(), largest > 0 else { return }
        // As large as fits: the biggest body at most 36% of the height, and the row of bodies within
        // the width. Every body keeps its true ratio to the others.
        let gap: CGFloat = 36
        let available = size.width * 0.86 - gap * CGFloat(bodies.count - 1)
        let totalRadius = CGFloat(bodies.map(\.radius).reduce(0, +))
        let scale = min(size.height * 0.36 / CGFloat(largest), available / 2 / totalRadius)
        let radii = bodies.map { CGFloat($0.radius) * scale }
        let drawn = radii.map { max($0, 1.5) }
        let total = drawn.map { $0 * 2 }.reduce(0, +) + gap * CGFloat(bodies.count - 1)
        var x = (size.width - total) / 2
        let y = size.height * 0.48

        for (i, body) in bodies.enumerated() {
            let r = drawn[i]
            let center = CGPoint(x: x + r, y: y)
            switch body.look {
            case .star(let t): drawStar(in: &context, center: center, radius: r, temperatureK: t)
            case .planet(let makeup): drawPlanet(in: &context, center: center, radius: r, makeup: makeup)
            }
            if body.isEstimate {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r - 4, y: center.y - r - 4, width: r * 2 + 8, height: r * 2 + 8)),
                               with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
            if radii[i] < 1.5 {
                // Too small to see at this scale: label it beside the dot, clear of its neighbour.
                let text = context.resolve(Text("\(body.name), too small to see at this scale").font(.system(size: 11)).foregroundColor(Color(white: 0.8)))
                let labelSize = text.measure(in: CGSize(width: size.width - center.x - 16, height: 40))
                context.draw(text, in: CGRect(x: center.x + 8, y: center.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height))
            } else {
                let text = context.resolve(Text(body.name).font(.system(size: 11)).foregroundColor(Color(white: 0.8)))
                let labelSize = text.measure(in: size)
                context.draw(text, at: CGPoint(x: min(max(center.x, labelSize.width / 2 + 8), size.width - labelSize.width / 2 - 8),
                                              y: min(y + max(r, 6) + 16, size.height - 30)))
            }
            x += r * 2 + gap
        }
    }

    private func drawStar(in context: inout GraphicsContext, center: CGPoint, radius r: CGFloat, temperatureK: Double?) {
        let base = StarColor.color(temperature: temperatureK ?? 5772)
        func shade(_ intensity: Double) -> Color {
            // Brighter toward the middle, keeping the star's hue.
            let lift = max(0, intensity - 0.75) * 1.6
            return Color(red: min(1, base.r * intensity + lift * 0.4), green: min(1, base.g * intensity + lift * 0.4), blue: min(1, base.b * intensity + lift * 0.4))
        }
        let glow = r * 1.9
        context.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [shade(1).opacity(0.45), shade(1).opacity(0)]), center: center, startRadius: r * 0.8, endRadius: glow))
        // Limb darkening, I(μ) = 1 − 0.6 (1 − μ), with μ = cos of the angle from the disc center.
        let stops = [0.0, 0.4, 0.6, 0.75, 0.85, 0.92, 0.97, 1.0].map { f -> Gradient.Stop in
            let mu = (1 - f * f).squareRoot()
            return .init(color: shade(1 - 0.6 * (1 - mu)), location: f)
        }
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: r))
    }

    private func drawPlanet(in context: inout GraphicsContext, center: CGPoint, radius r: CGFloat, makeup: PlanetComposition?) {
        let c = makeup?.color(dark: true) ?? StarColor.RGB(r: 0.7, g: 0.7, b: 0.72)
        let lit = Color(red: min(1, c.r * 1.25 + 0.08), green: min(1, c.g * 1.25 + 0.08), blue: min(1, c.b * 1.25 + 0.08))
        let mid = Color(red: c.r, green: c.g, blue: c.b)
        let dark = Color(red: c.r * 0.18, green: c.g * 0.18, blue: c.b * 0.18)
        // Lit from the upper left, as if by its star.
        let light = CGPoint(x: center.x - r * 0.4, y: center.y - r * 0.4)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(stops: [.init(color: lit, location: 0), .init(color: mid, location: 0.45), .init(color: dark, location: 1)]),
                                           center: light, startRadius: 0, endRadius: r * 1.6))
    }
}

/// A galaxy drawn from its measurements: its axis ratio (how tilted or flattened it looks), the
/// direction of its long axis on the sky (north up, east left) and its color (B−V). What isn't
/// measured follows its Hubble type: a bulge and disc, spiral arms as open as its stage (Sa tight,
/// Sc loose), or clumps for an irregular. The arms are a pattern, not this galaxy's own.
private struct GalaxyModelView: View {
    let model: FactHeader.GalaxyModel

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .background(Color(red: 0.02, green: 0.024, blue: 0.03))
            .overlay(alignment: .topLeading) { pill("Drawn from measurements") }
            .overlay(alignment: .bottomLeading) {
                Text(model.type == .spiral ? "Shape, tilt and color measured; arm pattern typical of its type" : "Shape, tilt and color measured")
                    .font(.system(size: 10)).foregroundColor(Color(white: 0.65)).padding(10)
            }
            .accessibilityElement()
            .accessibilityLabel("Drawing of the galaxy from its measured shape and color")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width * 0.4, size.height * 0.44 / CGFloat(max(model.axisRatio, 0.35)))
        let q = CGFloat(model.axisRatio)
        // Galaxy color on the star scale; young blue stars make spiral arms bluer than the bulge.
        let overall = StarColor.color(temperature: StarColor.temperature(bv: model.bMinusV ?? 0.7))
        let bulge = StarColor.color(temperature: StarColor.temperature(bv: max(model.bMinusV ?? 0.9, 0.85)))
        let arms = StarColor.color(temperature: StarColor.temperature(bv: min(model.bMinusV ?? 0.5, 0.45)))
        func color(_ c: StarColor.RGB, _ a: Double) -> Color { Color(red: c.r, green: c.g, blue: c.b).opacity(a) }

        var g = context
        g.translateBy(x: size.width / 2, y: size.height / 2)
        // Position angle runs from north (up) toward east (left), so the long axis points that way.
        let pa = model.positionAngleDeg * .pi / 180
        g.rotate(by: .radians(atan2(-cos(pa), -sin(pa))))
        g.scaleBy(x: 1, y: q)

        func blob(_ c: GraphicsContext, _ r: CGFloat, _ stops: [Gradient.Stop]) {
            c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: r))
        }

        switch model.type {
        case .elliptical, .lenticular, .dwarfSpheroidal, nil:
            // Smooth light falling off from the center (de Vaucouleurs-like), brightest in the core.
            let faint = model.type == .dwarfSpheroidal ? 0.35 : 1.0
            blob(g, radius, [.init(color: color(bulge, faint), location: 0), .init(color: color(overall, 0.55 * faint), location: 0.12),
                             .init(color: color(overall, 0.22 * faint), location: 0.4), .init(color: color(overall, 0), location: 1)])
            if model.type == .lenticular {
                // A thin disc around the bulge, without arms.
                var disc = g
                disc.scaleBy(x: 1, y: 0.45)
                blob(disc, radius * 0.95, [.init(color: color(overall, 0.3), location: 0), .init(color: color(overall, 0), location: 1)])
            }
        case .spiral:
            // Exponential disc.
            blob(g, radius, [.init(color: color(arms, 0.38), location: 0), .init(color: color(arms, 0.16), location: 0.45), .init(color: color(arms, 0), location: 1)])
            // Two logarithmic arms, r = r0·e^(kθ), with pitch angle by Hubble stage.
            let pitchDeg: Double = ["a": 8, "b": 13, "c": 20, "d": 26, "m": 30][model.stage ?? "b"] ?? 14
            let k = tan(pitchDeg * .pi / 180)
            var arm = g
            arm.addFilter(.blur(radius: max(radius * 0.035, 1.5)))
            let r0 = radius * 0.12
            for start in [0.0, Double.pi] {
                var theta = 0.0
                while true {
                    let r = r0 * CGFloat(exp(k * theta))
                    if r > radius * 0.95 { break }
                    let a = theta + start
                    let p = CGPoint(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a)) * r)
                    let dot = radius * 0.05 * (1 - r / radius * 0.5)
                    arm.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(color(arms, 0.55 * Double(1 - r / radius))))
                    theta += 0.06
                }
            }
            // Bulge.
            blob(g, radius * 0.28, [.init(color: color(bulge, 1), location: 0), .init(color: color(bulge, 0.5), location: 0.35), .init(color: color(bulge, 0), location: 1)])
        case .irregular:
            // Clumps of star formation scattered through a faint glow, placed by the galaxy's number.
            blob(g, radius, [.init(color: color(arms, 0.3), location: 0), .init(color: color(arms, 0), location: 1)])
            var seed = UInt64(truncatingIfNeeded: model.seed &* 2_654_435_761 | 1)
            func random() -> Double { seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; return Double(seed >> 11) / Double(1 << 53) }
            var clumps = g
            clumps.addFilter(.blur(radius: max(radius * 0.04, 1.5)))
            for _ in 0..<14 {
                let a = random() * 2 * .pi, d = sqrt(random()) * Double(radius) * 0.75
                let r = radius * CGFloat(0.06 + random() * 0.1)
                let p = CGPoint(x: cos(a) * d, y: sin(a) * d)
                clumps.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color(arms, 0.45 + random() * 0.3)))
            }
        }
    }
}
