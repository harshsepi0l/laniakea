import simd
import SwiftUI

/// Point the iPad at the sky: the camera with every naked-eye star, the planets and the Sun drawn
/// where they really are. Aim at something, or tap it, and a reticle locks onto it; it gets a live
/// corner map showing where it lives in Atlas, and its facts at the bottom.
struct SkyView: View {
    /// Leave the sky and show a place in Atlas, optionally focusing one of its objects.
    let onOpenInAtlas: (AtlasPlace, String?) -> Void
    /// Leave the sky and open a Solar System planet's card.
    let onOpenPlanet: (Planet) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SkyViewModel()
    @State private var optics: CameraOptics?
    @State private var selectedID: String?
    @State private var factSubject: FactSubject?
    @State private var orientation = 1
    @State private var dragStart: CGSize?
    @State private var zoomStart: Double?
    /// A tapped pick stays until you tap empty sky; otherwise whatever is nearest the middle is picked.
    @State private var isLocked = false
    private let cache = SkyDirectionCache()
    private let reticle = Reticle()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.016, green: 0.024, blue: 0.043).ignoresSafeArea()
                if model.usesMotion {
                    // Hidden while the view is dragged away from where the camera points.
                    CameraPreview(interfaceOrientation: orientation) { optics = $0 }
                        .ignoresSafeArea()
                        .opacity(model.isDragged ? 0 : 1)
                        .animation(.easeInOut(duration: 0.35), value: model.isDragged)
                }

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, date: timeline.date)
                    }
                }
                .ignoresSafeArea()
                .gesture(lookAroundGesture(size: geo.size))
                .simultaneousGesture(zoomGesture)
                .simultaneousGesture(SpatialTapGesture().onEnded { tap(at: $0.location, size: geo.size) })

                overlays(size: geo.size)
            }
            .onChange(of: geo.size) { _, _ in readOrientation() }
            .onChange(of: selectedID) { _, id in reticle.retarget(to: id) }
            .task(id: geo.size) { await pickLoop(size: geo.size) }
        }
        .background(Color.black)
        .statusBarHidden()
        .onAppear {
            readOrientation()
            model.start()
        }
        .onDisappear { model.stop() }
        .sheet(item: $factSubject) { FactSheetView(subject: $0) }
    }

    // MARK: Geometry

    private func readOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        orientation = scene?.interfaceOrientation.rawValue ?? 1
        model.interfaceOrientation = orientation
    }

    /// The overlay covers the whole screen, safe areas included, like the camera picture.
    private func fullSize(_ size: CGSize) -> CGSize {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return window?.bounds.size ?? size
    }

    private func projection(size: CGSize) -> SkyProjection {
        SkyProjection(pointing: model.pointing, size: fullSize(size), optics: model.usesMotion ? optics : nil)
    }

    private var selected: SkyObject? { model.objects.first { $0.id == selectedID } }

    // MARK: Picking

    /// Every fifth of a second, unless something was tapped, picks the object nearest the middle of
    /// the view, favouring bright ones and keeping the current pick until something clearly closer
    /// arrives.
    private func pickLoop(size: CGSize) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            guard !isLocked, let sky = model.localSky(at: Date()) else { continue }
            let proj = projection(size: size)
            let dirs = cache.directions(for: model.objects, sky: sky)
            let centre = CGPoint(x: proj.size.width / 2, y: proj.size.height / 2)
            var best: (id: String, score: Double)?
            for (object, dir) in zip(model.objects, dirs) {
                guard let p = proj.point(dir) else { continue }
                let d = hypot(p.x - centre.x, p.y - centre.y)
                guard d < 70 else { continue }
                var score = Double(d) + 9 * object.magnitude
                if object.id == selectedID { score -= 25 }
                if score < best?.score ?? .infinity { best = (object.id, score) }
            }
            if best?.id != selectedID {
                withAnimation(.easeInOut(duration: 0.2)) { selectedID = best?.id }
            }
        }
    }

    /// Picks what was tapped (the nearest object within a fingertip, favouring bright ones) and
    /// holds it; a tap on empty sky lets go.
    private func tap(at location: CGPoint, size: CGSize) {
        guard let sky = model.localSky(at: Date()) else { return }
        let proj = projection(size: size)
        let dirs = cache.directions(for: model.objects, sky: sky)
        var best: (id: String, score: Double)?
        for (object, dir) in zip(model.objects, dirs) {
            guard let p = proj.point(dir) else { continue }
            let d = Double(hypot(p.x - location.x, p.y - location.y))
            guard d < 44 else { continue }
            let score = d + 4 * object.magnitude
            if score < best?.score ?? .infinity { best = (object.id, score) }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if let best {
                selectedID = best.id
                isLocked = true
            } else {
                isLocked = false
                selectedID = nil
            }
        }
    }

    // MARK: Drawing

    private var here: Color { Color(red: 1.0, green: 0.69, blue: 0.36) }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        guard let sky = model.localSky(at: date) else { return }
        let proj = projection(size: size)
        let bounds = CGRect(origin: .zero, size: proj.size).insetBy(dx: -20, dy: -20)
        // The overlay is drawn in the full screen's coordinates; shift so its centre is the view's.
        context.translateBy(x: (size.width - proj.size.width) / 2, y: (size.height - proj.size.height) / 2)

        drawHorizon(in: &context, proj: proj)

        let dirs = cache.directions(for: model.objects, sky: sky)
        var selectedSpot: (point: CGPoint, half: CGFloat)?
        var bins: [Int: Path] = [:]
        var labels: [(String, CGPoint, CGFloat, Bool)] = []
        for (object, dir) in zip(model.objects, dirs) {
            guard let p = proj.point(dir), bounds.contains(p) else { continue }
            let isSelected = object.id == selectedID
            switch object.kind {
            case .star:
                let r = dotRadius(object)
                bins[StarColor.bin(temperature: object.temperatureK ?? 5772), default: Path()]
                    .addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                if object.magnitude < 1.6 || isSelected { labels.append((object.name, p, r, isSelected)) }
            case .planet:
                let color = object.composition.swiftUI(dark: true)
                glow(&context, p, 14, color)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(color))
                labels.append((object.name, p, 5, isSelected))
            case .sun:
                let color = StarColor.swiftUI(temperature: 5772, dark: true)
                glow(&context, p, 40, color)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)), with: .color(color))
                labels.append(("Sun", p, 11, isSelected))
            }
            if isSelected {
                selectedSpot = (p, object.id == "sun" ? 20 : max(dotRadius(object) + 9, 14))
            }
        }
        for (bin, path) in bins {
            context.fill(path, with: .color(StarColor.color(bin: bin).color(dark: true)))
        }
        // The reticle glides to a new pick, pulses once on arrival, then follows it.
        var reticleHalf: CGFloat = 0
        if let spot = selectedSpot {
            let now = reticle.current(target: spot.point, half: spot.half, date: date)
            reticleHalf = now.half
            drawReticle(in: &context, at: now.point, half: now.half, pulse: now.pulse)
        } else {
            reticle.clear()
        }
        for (text, p, r, isSelected) in labels {
            let resolved = context.resolve(Text(text).font(.system(size: isSelected ? 13 : 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? here : Color(white: 0.85)))
            let s = resolved.measure(in: proj.size)
            // The picked object's name goes outside its reticle.
            let rect = CGRect(x: p.x + (isSelected ? max(reticleHalf, r) + 8 : r + 6), y: p.y - s.height / 2, width: s.width, height: s.height)
            context.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -1), cornerRadius: 4), with: .color(.black.opacity(0.55)))
            context.draw(resolved, in: rect)
        }
    }

    /// A star's dot radius: brighter stars draw bigger.
    private func dotRadius(_ object: SkyObject) -> CGFloat {
        CGFloat(min(max(3.4 - 0.5 * object.magnitude, 0.7), 5))
    }

    /// Four corner brackets around the pick, and a ring that grows and fades when it arrives.
    private func drawReticle(in context: inout GraphicsContext, at p: CGPoint, half h: CGFloat, pulse: Double?) {
        let arm = min(8, h * 0.6)
        var brackets = Path()
        for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            let corner = CGPoint(x: p.x + CGFloat(sx) * h, y: p.y + CGFloat(sy) * h)
            brackets.move(to: CGPoint(x: corner.x, y: corner.y - CGFloat(sy) * arm))
            brackets.addLine(to: corner)
            brackets.addLine(to: CGPoint(x: corner.x - CGFloat(sx) * arm, y: corner.y))
        }
        context.stroke(brackets, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        context.stroke(brackets, with: .color(here), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if let pulse {
            let radius = h * (1 + CGFloat(pulse))
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(here.opacity(0.7 * (1 - pulse))), lineWidth: 1.5)
        }
    }

    private func glow(_ context: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]), center: p, startRadius: 0, endRadius: r))
    }

    /// The horizon as a line, with the compass points on it; below it is ground.
    private func drawHorizon(in context: inout GraphicsContext, proj: SkyProjection) {
        var line = Path()
        var started = false
        for step in 0...180 {
            let az = Double(step) * 2 * .pi / 180
            if let p = proj.point(LocalSky.direction(altitude: 0, azimuth: az)) {
                if started { line.addLine(to: p) } else { line.move(to: p); started = true }
            } else {
                started = false
            }
        }
        context.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1)
        for (name, deg) in [("N", 0.0), ("NE", 45), ("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)] {
            guard let p = proj.point(LocalSky.direction(altitude: 0, azimuth: deg * .pi / 180)) else { continue }
            let text = context.resolve(Text(name).font(.system(size: name.count == 1 ? 14 : 11, weight: .semibold)).foregroundColor(.white.opacity(0.75)))
            context.draw(text, at: CGPoint(x: p.x, y: p.y + 12))
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? model.pointing.zoom
                zoomStart = start
                model.pinch(to: start * Double(value.magnification))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func lookAroundGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? .zero
                dragStart = value.translation
                let delta = CGSize(width: value.translation.width - start.width, height: value.translation.height - start.height)
                model.drag(by: delta, degreesPerPoint: projection(size: size).widthDegrees / Double(size.width))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: Overlays

    private func overlays(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white).frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Close the sky view")
                statusPill
                Spacer(minLength: 8)
                SkyCornerMap(model: model, selected: selected, projection: { projection(size: size) })
                    .onTapGesture { openInAtlas() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Map. Opens in Atlas")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            SkyFactsPanel(model: model, object: selected, onFacts: openFacts, onOpenInAtlas: openInAtlas,
                          onConstellation: { factSubject = .constellation($0) })
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
        }
    }

    private var statusPill: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch model.locationState {
            case .denied:
                Text("Location is off").font(.system(size: 13, weight: .semibold))
                Text("Turn it on in Settings to see your sky").font(.system(size: 11))
            case .waiting:
                Text("Finding where you are…").font(.system(size: 13, weight: .semibold))
            case .ready:
                Text(isLocked ? "Tap empty sky to let go"
                     : model.isDragged ? "Back to where you point in a moment"
                     : model.usesMotion ? "Point, drag or tap" : "Drag or tap")
                    .font(.system(size: 13, weight: .semibold))
                if model.usesMotion, !model.isTrueNorth {
                    Text("Using the magnetic compass").font(.system(size: 11))
                }
            }
            if let error = model.error { Text(error).font(.system(size: 11)) }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Actions

    private func openFacts() {
        guard let object = selected else { return }
        switch object.kind {
        case .star(let star, let host): factSubject = host.map(FactSubject.starSystem) ?? .nakedEyeStar(star)
        case .sun: factSubject = .sun
        case .planet(let planet): onOpenPlanet(planet)
        }
    }

    private func openInAtlas() {
        guard let object = selected else { onOpenInAtlas(.milkyWay, nil); return }
        switch object.kind {
        case .star(let star, let host):
            onOpenInAtlas(.milkyWay, host.map { "star-\($0.id)" } ?? (star.distanceParsecs != nil ? "naked-\(star.id)" : nil))
        case .sun: onOpenInAtlas(.solarSystem, nil)
        case .planet(let planet): onOpenPlanet(planet)
        }
    }
}

/// Where the reticle is drawn: it eases from its last spot to a new pick over a quarter second,
/// then pulses once. A class, so the drawing can update it every frame without re-rendering views.
private final class Reticle {
    private var from: (point: CGPoint, half: CGFloat)?
    private var last: (point: CGPoint, half: CGFloat)?
    private var changedAt = Date.distantPast
    private static let glide = 0.28, pulseLength = 0.5

    func retarget(to id: String?) {
        from = id == nil ? nil : last
        changedAt = Date()
    }

    func clear() { last = nil }

    func current(target: CGPoint, half: CGFloat, date: Date) -> (point: CGPoint, half: CGFloat, pulse: Double?) {
        let elapsed = date.timeIntervalSince(changedAt)
        let t = min(max(elapsed / Self.glide, 0), 1)
        let ease = CGFloat(1 - pow(1 - t, 3))
        var point = target, size = half
        if let from, t < 1 {
            point = CGPoint(x: from.point.x + (target.x - from.point.x) * ease, y: from.point.y + (target.y - from.point.y) * ease)
            size = from.half + (half - from.half) * ease
        }
        last = (point, size)
        let sinceArrival = elapsed - (from == nil ? 0 : Self.glide)
        let pulse = (0...Self.pulseLength).contains(sinceArrival) ? sinceArrival / Self.pulseLength : nil
        return (point, size, pulse)
    }
}
