import simd
import SwiftUI

/// Point the device at the sky: the camera with every naked-eye star, the planets and the Sun drawn
/// where they really are. Aim at something, or tap it, and a reticle finds it; the lock button keeps
/// the reticle on it wherever you point next. It gets a live corner map showing where it lives in
/// Atlas, and its facts.
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
    @State private var moonSheet: Moon?
    @State private var orientation = 1
    @State private var dragStart: CGSize?
    @State private var zoomStart: Double?
    /// A tapped pick stays until you tap empty sky; otherwise whatever is nearest the middle is picked.
    @State private var isHeld = false
    /// Locked with the button: the reticle stays on the pick wherever you point, until unlocked.
    @State private var isLocked = false
    @State private var isPanelExpanded = false
    /// Set in Settings: the camera picture behind the sky, the corner map, the facts bubble, and
    /// the lock button.
    @AppStorage("sky.showsCamera") private var showsCamera = true
    @AppStorage("sky.showsMap") private var showsMap = true
    @AppStorage("sky.showsFacts") private var showsFacts = true
    @AppStorage("sky.showsLock") private var showsLock = true
    private let cache = SkyDirectionCache()
    /// Draws the naked-eye stars on the GPU; the overlay above draws everything else.
    @State private var starRenderer = SkyStarRenderer()
    private let reticle = Reticle()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.016, green: 0.024, blue: 0.043).ignoresSafeArea()
                if model.usesMotion, showsCamera {
                    // Hidden while the view is dragged away from where the camera points. Turned off
                    // in Settings, the camera stops and only the sky is drawn, still following the device.
                    CameraPreview(interfaceOrientation: orientation) { optics = $0 }
                        .ignoresSafeArea()
                        .opacity(model.isDragged ? 0 : 1)
                        .animation(.easeInOut(duration: 0.35), value: model.isDragged)
                }

                SkyStarView(renderer: starRenderer, objects: model.objects,
                            projection: { projection(size: geo.size) }, sky: { model.localSky(at: Date()) })
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, date: timeline.date)
                    }
                }
                .ignoresSafeArea()
                .gesture(lookAroundGesture(size: geo.size))
                .simultaneousGesture(zoomGesture)
                // In screen coordinates, the same ones the sky is drawn in; the view's own would be
                // shifted by the safe area (sideways in landscape).
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap(at: $0.location, size: geo.size) })

                overlays(size: geo.size)
            }
            .onChange(of: geo.size) { _, _ in readOrientation() }
            .onChange(of: selectedID) { _, id in reticle.retarget(to: id) }
            .onChange(of: showsLock) { _, on in if !on { isLocked = false } }
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
        .sheet(item: $moonSheet) { MoonDetailSheet(moon: $0, primaryName: "Earth") }
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
        // With the camera off, the last optics keep the sky the same size it was over the picture.
        SkyProjection(pointing: model.pointing, size: fullSize(size), optics: model.usesMotion ? optics : nil)
    }

    private var selected: SkyObject? { model.objects.first { $0.id == selectedID } }

    // MARK: Picking

    /// Every fifth of a second, unless something is held or locked, picks the object nearest the middle of
    /// the view, favouring bright ones and keeping the current pick until something clearly closer
    /// arrives.
    private func pickLoop(size: CGSize) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            guard !isLocked, !isHeld, let sky = model.localSky(at: Date()) else { continue }
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

    /// Locks the reticle on the current pick, or lets it go.
    private func toggleLock() {
        guard isLocked || selectedID != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            isLocked.toggle()
            if !isLocked { isHeld = false }
        }
    }

    /// Picks what was tapped (the nearest object within a fingertip; brightness only breaks near
    /// ties) and locks onto it, as the lock button would (or just holds it with the button turned
    /// off in Settings); a tap on empty sky lets go of a hold. While locked, taps change nothing.
    private func tap(at location: CGPoint, size: CGSize) {
        guard !isLocked, let sky = model.localSky(at: Date()) else { return }
        let proj = projection(size: size)
        let dirs = cache.directions(for: model.objects, sky: sky)
        var best: (id: String, score: Double)?
        for (object, dir) in zip(model.objects, dirs) {
            guard let p = proj.point(dir) else { continue }
            let d = Double(hypot(p.x - location.x, p.y - location.y))
            guard d < 44 else { continue }
            let score = d + 1.5 * object.magnitude
            if score < best?.score ?? .infinity { best = (object.id, score) }
        }
        if best != nil, showsLock { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedID = best?.id
            isHeld = best != nil
            isLocked = best != nil && showsLock
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
        let sunDirection = model.objects.firstIndex { $0.id == "sun" }.flatMap { $0 < dirs.count ? dirs[$0] : nil }
        var selectedSpot: (point: CGPoint, half: CGFloat)?
        var labels: [(String, CGPoint, CGFloat, Bool)] = []
        for (object, dir) in zip(model.objects, dirs) {
            let isSelected = object.id == selectedID
            // The stars' dots are drawn on the GPU (SkyStarView); here only the bright ones' names
            // and the pick need them.
            if case .star = object.kind, object.magnitude >= 1.6, !isSelected { continue }
            guard let p = proj.point(dir), bounds.contains(p) else { continue }
            switch object.kind {
            case .star:
                labels.append((object.name, p, dotRadius(object), isSelected))
            case .planet:
                // Sized by brightness like the stars, a little larger so the fainter planets stay findable.
                let color = object.composition.swiftUI(dark: true)
                let r = planetRadius(object)
                glow(&context, p, r * 3, color)
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                labels.append((object.name, p, r + 0.5, isSelected))
            case .sun:
                let color = StarColor.swiftUI(temperature: 5772, dark: true)
                glow(&context, p, 40, color)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)), with: .color(color))
                labels.append(("Sun", p, 11, isSelected))
            case .moon(let moon):
                let r = drawMoon(in: &context, at: p, moon: moon, direction: dir, sunDirection: sunDirection, proj: proj)
                labels.append(("Moon", p, r, isSelected))
                if isSelected { selectedSpot = (p, r + 7) }
                continue
            }
            if isSelected {
                selectedSpot = (p, object.id == "sun" ? 20 : max(dotRadius(object) + 9, 14))
            }
        }
        // The reticle glides to a new pick, pulses once on arrival, then follows it.
        var reticleHalf: CGFloat = 0
        if let spot = selectedSpot {
            let now = reticle.current(target: spot.point, half: spot.half, date: date)
            reticleHalf = now.half
            drawReticle(in: &context, at: now.point, half: now.half, pulse: now.pulse, isLocked: isLocked)
        } else {
            reticle.clear()
            // A locked or tapped pick that's out of view gets an arrow at the edge pointing to it.
            if isLocked || isHeld, let i = model.objects.firstIndex(where: { $0.id == selectedID }), i < dirs.count {
                drawPointer(in: &context, to: dirs[i], name: model.objects[i].name, proj: proj)
            }
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

    /// The Moon at its phase: the lit part faces the Sun, bounded by the limb on the Sun's side and
    /// the terminator, a half-ellipse whose width follows the lit fraction k (it spans 1 − 2k of the
    /// radius). Drawn at its true size when zoomed in enough, else at a size you can see.
    /// Returns the radius drawn.
    private func drawMoon(in context: inout GraphicsContext, at p: CGPoint, moon: MoonView, direction: SIMD3<Double>,
                          sunDirection: SIMD3<Double>?, proj: SkyProjection) -> CGFloat {
        let r = max(9, CGFloat(proj.focal * tan(moon.angularRadiusDeg * .pi / 180)))
        glow(&context, p, r * 2.4, Color(white: 0.9))
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .color(Color(white: 0.55).opacity(0.22)))
        context.stroke(disc, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
        // Which way the Sun lies across the screen from the Moon.
        var angle = -Double.pi / 2
        if let sun = sunDirection {
            let toward = sun - simd_dot(sun, direction) * direction
            let dx = simd_dot(toward, proj.right), dy = -simd_dot(toward, proj.up)
            if abs(dx) + abs(dy) > 1e-9 { angle = atan2(dy, dx) }
        }
        let k = moon.illuminatedFraction, e = 1 - 2 * k, steps = 36
        var lit = Path()
        for j in 0...steps {
            let t = -Double.pi / 2 + Double.pi * Double(j) / Double(steps)
            let point = CGPoint(x: Double(r) * cos(t), y: Double(r) * sin(t))
            if j == 0 { lit.move(to: point) } else { lit.addLine(to: point) }
        }
        for j in stride(from: steps, through: 0, by: -1) {
            let t = -Double.pi / 2 + Double.pi * Double(j) / Double(steps)
            lit.addLine(to: CGPoint(x: e * Double(r) * cos(t), y: Double(r) * sin(t)))
        }
        lit.closeSubpath()
        lit = lit.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
        context.fill(lit, with: .color(Color(white: 0.93)))
        return r
    }

    /// A star's dot radius: brighter stars draw bigger.
    private func dotRadius(_ object: SkyObject) -> CGFloat {
        CGFloat(min(max(3.4 - 0.5 * object.magnitude, 0.7), 5))
    }

    /// A planet's dot radius: the star scale one point larger, from 1.5 (Neptune) to 5.5 (Venus).
    private func planetRadius(_ object: SkyObject) -> CGFloat {
        CGFloat(min(max(4.4 - 0.5 * object.magnitude, 1.5), 5.5))
    }

    /// Four corner brackets around the pick, and a ring that grows and fades when it arrives.
    /// Locked, the brackets close into a square.
    private func drawReticle(in context: inout GraphicsContext, at p: CGPoint, half h: CGFloat, pulse: Double?, isLocked: Bool) {
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
        if isLocked {
            context.stroke(Path(roundedRect: CGRect(x: p.x - h, y: p.y - h, width: h * 2, height: h * 2), cornerRadius: 3),
                           with: .color(here.opacity(0.55)), lineWidth: 1)
        }
        if let pulse {
            let radius = h * (1 + CGFloat(pulse))
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(here.opacity(0.7 * (1 - pulse))), lineWidth: 1.5)
        }
    }

    /// An arrow at the screen's edge toward an object out of view, with its name.
    private func drawPointer(in context: inout GraphicsContext, to direction: SIMD3<Double>, name: String, proj: SkyProjection) {
        // Which way to turn: the object's direction across the screen, even when it's behind you.
        var v = CGVector(dx: simd_dot(direction, proj.right), dy: -simd_dot(direction, proj.up))
        let length = hypot(v.dx, v.dy)
        if length < 1e-6 { v = CGVector(dx: 0, dy: 1) } else { v = CGVector(dx: v.dx / length, dy: v.dy / length) }
        // Kept clear of the controls at the top and bottom.
        let area = CGRect(x: 36, y: 140, width: proj.size.width - 72, height: proj.size.height - 260)
        let centre = CGPoint(x: area.midX, y: area.midY)
        let t = min(v.dx == 0 ? .infinity : area.width / 2 / abs(v.dx), v.dy == 0 ? .infinity : area.height / 2 / abs(v.dy))
        let tip = CGPoint(x: centre.x + v.dx * t, y: centre.y + v.dy * t)
        let angle = atan2(v.dy, v.dx)
        var arrow = Path()
        arrow.move(to: CGPoint(x: 13, y: 0))
        arrow.addLine(to: CGPoint(x: -8, y: -10))
        arrow.addLine(to: CGPoint(x: -3, y: 0))
        arrow.addLine(to: CGPoint(x: -8, y: 10))
        arrow.closeSubpath()
        arrow = arrow.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: tip.x, y: tip.y))
        context.fill(arrow, with: .color(here))
        context.stroke(arrow, with: .color(.black.opacity(0.5)), lineWidth: 1)
        // The name sits inward from the arrow.
        let text = context.resolve(Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(here))
        let size = text.measure(in: proj.size)
        let at = CGPoint(x: tip.x - v.dx * (size.width / 2 + 22), y: tip.y - v.dy * (size.height / 2 + 22))
        let rect = CGRect(x: at.x - size.width / 2, y: at.y - size.height / 2, width: size.width, height: size.height)
        context.fill(Path(roundedRect: rect.insetBy(dx: -5, dy: -2), cornerRadius: 5), with: .color(.black.opacity(0.6)))
        context.draw(text, in: rect)
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
                if showsMap {
                    SkyCornerMap(model: model, selected: selected, projection: { projection(size: size) })
                        .onTapGesture { openInAtlas() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Map. Opens in Atlas")
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: showsMap)
            Spacer()
            HStack(alignment: .bottom, spacing: 10) {
                if showsFacts {
                    SkyFactsPanel(model: model, object: selected, isExpanded: $isPanelExpanded, onFacts: openFacts,
                                  onOpenInAtlas: openInAtlas, onConstellation: { factSubject = .constellation($0) })
                }
                Spacer(minLength: 0)
                if showsLock { lockButton }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    /// Locks the reticle on the pick, wherever you point next; tap again to unlock.
    private var lockButton: some View {
        Button(action: toggleLock) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(isLocked ? .black : .white)
                .frame(width: 54, height: 54)
                .background(isLocked ? here : Color(white: 0.11).opacity(0.9), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(isLocked ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!isLocked && selectedID == nil)
        .opacity(!isLocked && selectedID == nil ? 0.45 : 1)
        .accessibilityLabel(isLocked ? "Unlock \(selected?.name ?? "")" : "Lock on \(selected?.name ?? "the pick")")
    }

    private var statusPill: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch model.locationState {
            case .denied:
                Text("Location is off").font(.system(size: 13, weight: .semibold))
                Text("Turn it on in the Settings app to see your sky").font(.system(size: 11))
            case .waiting:
                Text("Finding where you are…").font(.system(size: 13, weight: .semibold))
            case .ready:
                Text(isLocked ? "Locked on \(selected?.name ?? "it")"
                     : isHeld ? "Tap empty sky to let go"
                     : model.isDragged ? "Back to where you point in a moment"
                     : model.usesMotion ? "Point, drag or tap" : "Drag or tap")
                    .font(.system(size: 13, weight: .semibold))
                if model.usesMotion, !model.isTrueNorth {
                    Text("Using the magnetic compass").font(.system(size: 11))
                }
            }
            if let error = model.error { Text(error).font(.system(size: 11)) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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
        case .moon: if let moon = model.moonDetails { moonSheet = moon } else { openEarth() }
        }
    }

    /// The Moon lives with Earth in Atlas: Earth's card shows its moon.
    private func openEarth() {
        guard let earth = model.planets.first(where: { $0.id == Planet.earthID }) else { onOpenInAtlas(.solarSystem, nil); return }
        onOpenPlanet(earth)
    }

    private func openInAtlas() {
        guard let object = selected else { onOpenInAtlas(.milkyWay, nil); return }
        switch object.kind {
        case .star(let star, let host):
            onOpenInAtlas(.milkyWay, host.map { "star-\($0.id)" } ?? (star.distanceParsecs != nil ? "naked-\(star.id)" : nil))
        case .sun: onOpenInAtlas(.solarSystem, nil)
        case .planet(let planet): onOpenPlanet(planet)
        case .moon: openEarth()
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
