import simd
import SwiftUI

/// The solar system as glowing dots with motion trails. Flat (top-down) by default; pinching in tilts it
/// into a 3D perspective with bigger, easier-to-tap planets.
struct SolarSystemView: View {
    let planets: [Planet]
    @ObservedObject var clock: SimulationClock
    let selectedPlanetID: String?
    let onSelect: (Planet) -> Void

    @Environment(\.colorScheme) private var colorScheme

    // Tilt between flat (0) and 3D (1), animated or driven live by a pinch.
    @State private var tiltFrom: Double = 0
    @State private var tiltTo: Double = 0
    @State private var tiltStart = Date.distantPast
    @State private var pinchTilt: Double?
    @State private var isAnimatingTilt = false
    @State private var showObjects = false
    // Flat view: a small rubber-banded drag. 3D view: zoom around the pinch, and pan within the zoomed area.
    @State private var rawPan: CGSize = .zero
    @State private var rawPanStart: CGSize?
    @State private var freePan: CGSize = .zero
    @State private var freePanStart: CGSize?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?

    private static let panLimit: CGFloat = 70
    private static let maxZoom: CGFloat = 60

    private var isIn3DMode: Bool { tiltTo > 0.5 }

    private var pan: CGSize {
        isIn3DMode
            ? freePan
            : CGSize(width: Self.rubberBand(rawPan.width), height: Self.rubberBand(rawPan.height))
    }

    /// Applies zoom (around the view center) and pan to a projected point.
    private func place(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (p.x - size.width / 2) * zoom + pan.width,
            y: size.height / 2 + (p.y - size.height / 2) * zoom + pan.height
        )
    }

    private func clampedPan(_ p: CGSize, size: CGSize) -> CGSize {
        let limitX = Self.panLimit + (zoom - 1) * size.width * 0.6
        let limitY = Self.panLimit + (zoom - 1) * size.height * 0.6
        return CGSize(width: min(max(p.width, -limitX), limitX), height: min(max(p.height, -limitY), limitY))
    }

    private static func rubberBand(_ x: CGFloat) -> CGFloat {
        let magnitude = panLimit * (1 - 1 / (abs(x) / panLimit + 1))
        return x < 0 ? -magnitude : magnitude
    }

    private static let tiltDuration: Double = 0.45
    private static let trailFraction: Double = 55.0 / 360
    private static let trailSegments = 24

    private var is3D: Bool { (pinchTilt ?? tiltTo) > 0.5 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                TimelineView(.animation(paused: !(clock.isPlaying || isAnimatingTilt || pinchTilt != nil))) { timeline in
                    let _ = clock.tick(now: timeline.date)
                    let camera = camera(size: geo.size, tilt: tilt(at: timeline.date))
                    Canvas { context, _ in
                        draw(in: &context, camera: camera)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let cam = camera(size: geo.size, tilt: tilt(at: Date()))
                            if let planet = planet(at: value.location, camera: cam) {
                                onSelect(planet)
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if isIn3DMode {
                                let start = freePanStart ?? freePan
                                freePanStart = start
                                freePan = clampedPan(
                                    CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                                    size: geo.size
                                )
                            } else {
                                let start = rawPanStart ?? rawPan
                                rawPanStart = start
                                rawPan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                            }
                        }
                        .onEnded { _ in
                            rawPanStart = nil
                            freePanStart = nil
                            let cap = Self.panLimit * 3
                            rawPan = CGSize(width: min(max(rawPan.width, -cap), cap), height: min(max(rawPan.height, -cap), cap))
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if isIn3DMode {
                                zoomAround(value.startLocation, magnification: value.magnification, size: geo.size)
                            } else {
                                pinchTilt = min(max((Double(value.magnification) - 1) * 1.6, 0), 1)
                            }
                        }
                        .onEnded { value in
                            if isIn3DMode {
                                // Pinching out past the starting zoom returns to the flat view.
                                let wanted = (zoomStart ?? zoom) * value.magnification
                                zoomStart = nil
                                freePanStart = nil
                                if wanted < 0.8 { animateTilt(from: 1, to: 0) }
                            } else {
                                let current = pinchTilt ?? 0
                                pinchTilt = nil
                                animateTilt(from: current, to: current > 0.3 ? 1 : 0)
                            }
                        }
                )

                objectsPanel
                    .padding(.top, 64)
                    .padding(.bottom, 8)

                Button {
                    animateTilt(from: tiltTo, to: is3D ? 0 : 1)
                } label: {
                    Text(is3D ? "2D" : "3D")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6), in: Circle())
                }
                .accessibilityLabel(is3D ? "Switch to flat view" : "Switch to 3D view")
                .padding(.top, 64)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: is3D)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of the solar system")
        .accessibilityHint("Pinch in or use the 3D button for a 3D view")
        .accessibilityAction(named: is3D ? "Switch to flat view" : "Switch to 3D view") {
            animateTilt(from: tiltTo, to: is3D ? 0 : 1)
        }
    }

    // MARK: Objects panel

    private var objectsPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            if !showObjects {
                Button {
                    showObjects = true
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6), in: Circle())
                }
                .accessibilityLabel("Show objects")
                .padding(.trailing, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Objects")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showObjects = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Hide objects")
                    }
                    .padding(.leading, 16)

                    ForEach(planets) { planet in
                        Button {
                            onSelect(planet)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(planet.id == selectedPlanetID ? Color.orange : Color.primary)
                                    .frame(width: dotSize(planet), height: dotSize(planet))
                                    .frame(width: 14)
                                Text(planet.name)
                                    .font(.system(size: 15))
                                    .foregroundColor(planet.id == selectedPlanetID ? .orange : .primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 168)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                        .fill(Color(.systemGray6))
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showObjects)
    }

    private func dotSize(_ planet: Planet) -> CGFloat {
        4 + 6 * CGFloat((planet.diameterKm / 142_984).squareRoot())
    }

    // MARK: Zoom

    /// Zooms so the point under the pinch stays put.
    private func zoomAround(_ anchor: CGPoint, magnification: CGFloat, size: CGSize) {
        let startZoom = zoomStart ?? zoom
        let startPan = freePanStart ?? freePan
        zoomStart = startZoom
        freePanStart = startPan
        let newZoom = min(max(startZoom * magnification, 1), Self.maxZoom)
        let ratio = newZoom / startZoom
        let cx = size.width / 2, cy = size.height / 2
        zoom = newZoom
        freePan = clampedPan(
            CGSize(
                width: anchor.x - cx - (anchor.x - cx - startPan.width) * ratio,
                height: anchor.y - cy - (anchor.y - cy - startPan.height) * ratio
            ),
            size: size
        )
    }

    // MARK: Tilt

    private func tilt(at date: Date) -> Double {
        if let pinchTilt { return pinchTilt }
        let progress = min(max(date.timeIntervalSince(tiltStart) / Self.tiltDuration, 0), 1)
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        return tiltFrom + (tiltTo - tiltFrom) * eased
    }

    private func animateTilt(from: Double, to: Double) {
        if to > 0.5 {
            freePan = pan
        } else {
            rawPan = .zero
        }
        zoom = 1
        tiltFrom = from
        tiltTo = to
        tiltStart = Date()
        isAnimatingTilt = true
        Task {
            try? await Task.sleep(for: .seconds(Self.tiltDuration + 0.05))
            isAnimatingTilt = false
        }
    }

    private func camera(size: CGSize, tilt t: Double) -> TiltCamera {
        TiltCamera(size: size, tilt: t)
    }

    // MARK: Drawing

    private var ink: Color { colorScheme == .dark ? .white : Color(white: 0.07) }
    private var sunCore: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.69, blue: 0.36) : Color(red: 1.0, green: 0.48, blue: 0.10)
    }

    private func draw(in context: inout GraphicsContext, camera: TiltCamera) {
        let dark = colorScheme == .dark
        let date = clock.simulatedDate

        // Sun glow and core.
        if let projected = camera.project(.zero) {
            let sun = (point: place(projected.point, in: camera.size), scale: projected.scale)
            let glow = 52 * sun.scale
            context.fill(
                circle(sun.point, glow),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: sunCore.opacity(dark ? 0.55 : 0.5), location: 0),
                        .init(color: sunCore.opacity(dark ? 0.18 : 0.16), location: 0.35),
                        .init(color: sunCore.opacity(0), location: 1),
                    ]),
                    center: sun.point, startRadius: 0, endRadius: glow
                )
            )
            context.fill(circle(sun.point, (dark ? 7 : 8) * sun.scale), with: .color(sunCore))
        }

        struct Placed { let planet: Planet; let point: CGPoint; let radius: CGFloat; let depth: Double }
        var placed: [Placed] = []

        for planet in planets {
            // Trail: where the planet was over the last stretch of its orbit, fading toward the past.
            let span = planet.orbitalPeriodDays * 86_400 * Self.trailFraction
            var previous: CGPoint?
            for k in 0...Self.trailSegments {
                let when = date.addingTimeInterval(-span * (1 - Double(k) / Double(Self.trailSegments)))
                guard let au = PlanetEphemeris.position(of: planet.id, at: when),
                      let p = camera.project(SceneSpace.position(au))
                else { previous = nil; continue }
                let point = place(p.point, in: camera.size)
                if let previous {
                    var segment = Path()
                    segment.move(to: previous)
                    segment.addLine(to: point)
                    let alpha = (dark ? 0.3 : 0.25) * Double(k) / Double(Self.trailSegments)
                    context.stroke(segment, with: .color(ink.opacity(alpha)), style: StrokeStyle(lineWidth: 1.6 * p.scale, lineCap: .round))
                }
                previous = point
            }

            guard let au = PlanetEphemeris.position(of: planet.id, at: date),
                  let p = camera.project(SceneSpace.position(au))
            else { continue }
            placed.append(Placed(planet: planet, point: place(p.point, in: camera.size), radius: baseRadius(planet) * p.scale * camera.dotGrowth, depth: p.depth))
        }

        // Far planets first so nearer ones draw on top in 3D.
        for item in placed.sorted(by: { $0.depth > $1.depth }) {
            let selected = item.planet.id == selectedPlanetID
            let color = selected ? Color.orange : ink
            let glow = item.radius * 3.2
            context.fill(
                circle(item.point, glow),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(dark ? 0.28 : 0.16), color.opacity(0)]),
                    center: item.point, startRadius: 0, endRadius: glow
                )
            )
            context.fill(circle(item.point, item.radius), with: .color(color))
        }

        drawLabels(in: &context, placed: placed.map { ($0.planet, $0.point, $0.radius) }, size: camera.size)
    }

    private func drawLabels(in context: inout GraphicsContext, placed: [(Planet, CGPoint, CGFloat)], size: CGSize) {
        var taken = placed.map { _, p, r in CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2) }
        let bounds = CGRect(origin: .zero, size: size)
        for (planet, p, r) in placed {
            let label = context.resolve(
                Text(planet.name).font(.system(size: is3D ? 12 : 10.5)).foregroundColor(.secondary)
            )
            let s = label.measure(in: size)
            let candidates = [
                CGRect(x: p.x + r + 5, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - r - 5 - s.width, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y - r - 3 - s.height, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y + r + 3, width: s.width, height: s.height),
            ]
            if let rect = candidates.first(where: { rect in bounds.contains(rect) && !taken.contains { $0.intersects(rect) } }) {
                taken.append(rect)
                context.draw(label, in: rect)
            }
        }
    }

    private func circle(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private func baseRadius(_ planet: Planet) -> CGFloat {
        2.2 + 3.8 * CGFloat((planet.diameterKm / 142_984).squareRoot())
    }

    private func planet(at point: CGPoint, camera: TiltCamera) -> Planet? {
        let radius: CGFloat = is3D ? 40 : 28
        var best: (planet: Planet, distance: CGFloat)?
        for planet in planets {
            guard let au = PlanetEphemeris.position(of: planet.id, at: clock.simulatedDate),
                  let projected = camera.project(SceneSpace.position(au))?.point
            else { continue }
            let p = place(projected, in: camera.size)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < radius, d < (best?.distance ?? .infinity) {
                best = (planet, d)
            }
        }
        return best?.planet
    }
}

/// A camera that blends from straight overhead (tilt 0, looks flat) to a low 3D angle (tilt 1) that
/// is zoomed in with bigger dots.
struct TiltCamera {
    let size: CGSize
    let tilt: Double

    private static let fovDegrees = 50.0
    private static let flatPitch = 89.5 * Double.pi / 180
    private static let tiltedPitch = 42.0 * Double.pi / 180

    private var pixelsPerUnit: Double { Double(size.width) / 2 / tan(Self.fovDegrees / 2 * .pi / 180) }

    /// Camera distance at which the outermost orbit fills the view when seen from overhead.
    private var flatDistance: Double {
        SceneSpace.outerRadius * pixelsPerUnit / (Double(min(size.width, size.height)) / 2 * 0.98)
    }

    private var pitch: Double { Self.flatPitch + (Self.tiltedPitch - Self.flatPitch) * tilt }
    private var distance: Double { flatDistance * (1 - 0.12 * tilt) }
    /// Extra planet-dot size in 3D so planets are easier to see and tap.
    var dotGrowth: CGFloat { 1 + 0.8 * CGFloat(tilt) }

    /// Screen point, perspective size multiplier and depth of a flat layout point (on the ecliptic plane).
    func project(_ layout: SIMD2<Double>) -> (point: CGPoint, scale: CGFloat, depth: Double)? {
        let world = SIMD3(layout.x, 0, -layout.y)
        let eye = SIMD3(0, distance * sin(pitch), distance * cos(pitch))
        let forward = simd_normalize(-eye)
        let right = SIMD3<Double>(1, 0, 0)
        let up = simd_cross(right, forward)
        let ray = world - eye
        let depth = simd_dot(ray, forward)
        guard depth > 0.05 else { return nil }
        return (
            CGPoint(
                x: Double(size.width) / 2 + simd_dot(ray, right) / depth * pixelsPerUnit,
                y: Double(size.height) / 2 - simd_dot(ray, up) / depth * pixelsPerUnit
            ),
            CGFloat(min(flatDistance / depth, 1.6)),
            depth
        )
    }
}
