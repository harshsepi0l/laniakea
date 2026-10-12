import CoreImage
import simd
import SwiftUI

/// An Obsidian-style graph of real objects at their real positions: glowing dots, links to
/// neighbours, and selection that highlights a dot's links. Flat, it's seen from above; in 3D it
/// tilts and turns. Pinch to zoom, drag to move (in 3D one finger turns and two move), tap a dot to
/// select it, tap it again (or Open) to go inside, or tap the info button for its facts. Where
/// motion is measured, time can run forward and back.
///
/// The map is drawn with Metal (`GraphRenderer`), which moves with the camera at no cost per object;
/// names are drawn on top by SwiftUI once the map comes to rest.
struct CosmicGraphView: View {
    let scene: GraphScene
    @Binding var focusID: String?
    /// Which nodes the filter shows; nil shows them all.
    var visible: [Bool]? = nil
    let onOpen: (AtlasPlace) -> Void
    let onFacts: (FactSubject) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Draws the map and holds the live camera, which gestures move without touching SwiftUI state.
    @State private var renderer = GraphRenderer()
    /// Where the camera was when the map last came to rest; names and the scale bar use it.
    @State private var rest = GraphCameraState()
    /// The map is being dragged, pinched or animated; names hide until it stops.
    @State private var isMoving = false
    @State private var selected: Int?
    /// Laniakea's soft orange fill, blurred once into an image instead of on every frame.
    @State private var regionImage: RegionImage?
    /// How many objects the filter shows, counted when the filter changes rather than every frame.
    @State private var shownCount: Int?
    /// The objects list, switched from Atlas's controls.
    @Binding var showObjects: Bool
    /// The 3D view, switched from Atlas's controls.
    @Binding var is3D: Bool
    /// Time for this place; it only runs when simulations are on and something here has measured motion.
    @ObservedObject var clock: DeepTimeClock
    var runsTime = false
    /// Space under the scale bar and caption: level with the search button, or above the open
    /// search field.
    var bottomInset: CGFloat = AtlasChrome.bottomInset

    /// Set in Settings: the cosmic flow lines, the cosmic web, and Laniakea's boundary.
    @AppStorage("atlas.showsFlow") private var showsFlow = true
    @AppStorage("atlas.showsWeb") private var showsWeb = true
    @AppStorage("atlas.showsBoundary") private var showsBoundary = true

    private var timeClock: DeepTimeClock? { runsTime && scene.motion != nil ? clock : nil }
    private var years: Double { timeClock?.years ?? 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                GraphMetalView(renderer: renderer, content: GraphRenderer.Content(
                    scene: scene, visible: visible, selected: selected, dark: colorScheme == .dark,
                    regionImage: regionImage, clock: timeClock,
                    overlays: .init(flow: showsFlow, web: showsWeb, boundary: showsBoundary)
                ))
                .allowsHitTesting(false)
                Canvas { context, size in
                    drawLabels(in: &context, size: size)
                }
                // Names stay put while the map or time moves, then catch up.
                .opacity(isMoving || timeClock?.isPlaying == true ? 0 : 1)
                .allowsHitTesting(false)
                // Fade the top edge so objects don't stop at a hard line under the status bar.
                LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.05)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                // Takes the touches for the map.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            let hit = node(at: value.location, size: geo.size)
                            if let hit, hit == selected, let place = scene.nodes[hit].opens {
                                onOpen(place)
                            } else if let hit, hit == selected, let facts = scene.nodes[hit].facts {
                                // Nothing inside to open (a single galaxy), so a second tap shows its facts.
                                onFacts(facts)
                            } else {
                                selected = hit
                            }
                        }
                    )
                    .gesture(MapPanGesture { recognizer in pan(recognizer, size: geo.size) })
                    .gesture(MapPinchGesture { recognizer, anchor in pinch(recognizer, anchor: anchor, size: geo.size) })
                    .gesture(MapRotateGesture { recognizer in rotate(recognizer) })

                objectsPanel(size: geo.size)
                    .padding(.top, AtlasChrome.panelTop)
                    .padding(.bottom, AtlasChrome.panelBottom)

                VStack(alignment: .leading, spacing: 10) {
                    Spacer()
                    // The scale stays above the picked object's card, which sits by the search button.
                    scaleBar(size: geo.size)
                    if let selected {
                        selectionCard(scene.nodes[selected])
                    }
                }
                .padding(.leading, 16)
                // Clear of the search button in the bottom-right corner.
                .padding(.trailing, AtlasChrome.cornerButton + 24)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(selected != nil)
                .animation(.easeInOut(duration: 0.2), value: bottomInset)
            }
            .onChange(of: visible) { _, _ in
                if let selected, !isVisible(selected) { self.selected = nil }
                countShown()
            }
            .onAppear {
                countShown()
                // A new map opens straight in 3D when 3D is on.
                if is3D {
                    renderer.camera.state.tilt = GraphCameraState.tilt3D
                    renderer.camera.state.target.z = scene.fitDepth
                    if let r = scene.fitRadius3D { renderer.camera.state.zoom = min(1, scene.fitRadius / r) }
                    rest = renderer.camera.state
                }
            }
            .onChange(of: is3D) { _, on in setTilt(on) }
            .task(id: scene.region?.cells.count) {
                guard let region = scene.region else { return }
                regionImage = await Task.detached(priority: .userInitiated) { RegionImage(region) }.value
            }
            .onChange(of: focusID) { _, id in
                guard let id, let index = scene.nodes.firstIndex(where: { $0.id == id }) else { return }
                focus(on: index, size: geo.size)
                focusID = nil
            }
            // A focus asked for before this map existed (arriving from the sky view).
            .onAppear {
                guard let id = focusID, let index = scene.nodes.firstIndex(where: { $0.id == id }) else { return }
                focus(on: index, size: geo.size)
                focusID = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scene.caption)
    }

    // MARK: Geometry

    private func baseScale(_ size: CGSize) -> Double {
        Double(min(size.width, size.height)) / 2 * 0.92 / scene.fitRadius
    }

    private var zoom: CGFloat { CGFloat(rest.zoom) }

    /// Small for most objects so thousands stay legible; grows a little as you zoom in.
    private func dotRadius(_ node: GraphNode) -> CGFloat {
        (0.7 + 4.6 * CGFloat(pow(node.size, 1.6))) * min(pow(zoom, 0.35), 3)
    }

    /// Below this size a node is drawn faint and unlabeled; it falls as you zoom in.
    private var detailThreshold: Double { 0.42 / Double(pow(zoom, 0.5)) }

    private func isVisible(_ i: Int) -> Bool { visible?[i] ?? true }

    /// Screen points of every node for a camera, at the clock's time; far off screen when behind
    /// the camera.
    private func screenPoints(_ state: GraphCameraState, size: CGSize) -> [CGPoint] {
        let projection = GraphProjection(scene: scene, state: state, size: size)
        let t = years
        return scene.nodes.map { projection.point($0.position(atYears: t))?.point ?? CGPoint(x: -1e6, y: -1e6) }
    }

    private func beginMoving() {
        if !isMoving { isMoving = true }
    }

    /// The map has stopped: names and the scale bar catch up with the camera.
    private func settle() {
        let camera = renderer.camera
        guard camera.activeGestures == 0, !camera.isAnimating else { return }
        rest = camera.state
        isMoving = false
    }

    private func node(at point: CGPoint, size: CGSize) -> Int? {
        let points = screenPoints(renderer.camera.state, size: size)
        var best: (Int, CGFloat)?
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            let p = points[i]
            let d = hypot(p.x - point.x, p.y - point.y) + (n.size < detailThreshold ? 6 : 0)
            if d < max(22, dotRadius(n) + 8), d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    /// One finger moves the map anywhere. In 3D, two fingers sliding up or down tilt it, as in Maps.
    private func pan(_ recognizer: UIPanGestureRecognizer, size: CGSize) {
        let camera = renderer.camera
        switch recognizer.state {
        case .began:
            camera.activeGestures += 1
            beginMoving()
        case .changed:
            let t = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            var state = camera.state
            if state.is3D && recognizer.numberOfTouches == 2 {
                // Two fingers sliding together tilt, but only once that's clearly what they're
                // doing and not a pinch or a twist.
                var g = camera.twoFinger
                g.slide += t.y
                // Fingers that stay the same distance apart while sliding: a pinch spreads them.
                if !g.zooms && !g.turns && abs(g.slide) > 30 && abs(log(g.pinch)) < 0.03 { g.tilts = true }
                camera.twoFinger = g
                if g.tilts {
                    state.tilt = min(max(state.tilt - Double(t.y) * 0.005, 0.15), GraphCameraState.maxTilt)
                }
            } else {
                let projection = GraphProjection(scene: scene, state: state, size: size)
                state.target -= projection.layoutDelta(screen: CGSize(width: t.x, height: t.y))
            }
            camera.state = state
            camera.changed()
        default:
            camera.activeGestures = max(camera.activeGestures - 1, 0)
            settle()
        }
    }

    /// Two fingers twisting turn the 3D map around the middle of the screen.
    private func rotate(_ recognizer: UIRotationGestureRecognizer) {
        let camera = renderer.camera
        switch recognizer.state {
        case .began:
            camera.activeGestures += 1
            beginMoving()
        case .changed:
            guard camera.state.is3D else { recognizer.rotation = 0; return }
            // A small twist comes with most pinches; turn only once it's deliberate.
            var g = camera.twoFinger
            g.twist += recognizer.rotation
            if !g.tilts && abs(g.twist) > 0.25 { g.turns = true }
            camera.twoFinger = g
            if g.turns { camera.state.yaw -= Double(recognizer.rotation) }
            recognizer.rotation = 0
            camera.changed()
        default:
            camera.activeGestures = max(camera.activeGestures - 1, 0)
            settle()
        }
    }

    /// Zooms toward what's between the fingers, keeping it under them: in 3D, the nearest object
    /// to the fingers at its own depth, so you can zoom right into it.
    private func pinch(_ recognizer: UIPinchGestureRecognizer, anchor: CGPoint, size: CGSize) {
        let camera = renderer.camera
        switch recognizer.state {
        case .began:
            camera.activeGestures += 1
            camera.pinchPivot = pinchPivot(anchor: anchor, size: size)
            beginMoving()
        case .changed:
            var g = camera.twoFinger
            g.pinch *= recognizer.scale
            // Any clear spread is a zoom, even if it began as a slide.
            if abs(log(g.pinch)) > 0.05 { g.zooms = true; g.tilts = false }
            camera.twoFinger = g
            // Fingers sliding to tilt spread a little too; don't zoom then.
            let scale = g.tilts ? 1 : Double(recognizer.scale)
            recognizer.scale = 1
            var state = camera.state
            let zoom = min(max(state.zoom * scale, scene.minZoom), GraphCameraState.maxZoom)
            let s = zoom / state.zoom
            // Moving the target toward the pivot by the zoom ratio keeps the pivot exactly where it
            // is on screen, perspective included (the camera's distance shrinks with the zoom).
            let pivot = camera.pinchPivot ?? state.target
            state.target = pivot + (state.target - pivot) / s
            state.zoom = zoom
            camera.state = state
            camera.changed()
        default:
            camera.activeGestures = max(camera.activeGestures - 1, 0)
            camera.pinchPivot = nil
            settle()
        }
    }

    /// What a pinch zooms toward: in 3D the object drawn nearest the fingers (within a thumb's
    /// reach), else the point under them at the depth of the screen's middle.
    private func pinchPivot(anchor: CGPoint, size: CGSize) -> SIMD3<Double> {
        let state = renderer.camera.state
        let projection = GraphProjection(scene: scene, state: state, size: size)
        let offset = CGSize(width: anchor.x - size.width / 2, height: anchor.y - size.height / 2)
        let plane = state.target + projection.layoutDelta(screen: offset)
        guard state.is3D else { return plane }
        let t = years
        var best: (index: Int, distance: CGFloat)?
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            guard let p = projection.point(n.position(atYears: t)) else { continue }
            let d = hypot(p.point.x - anchor.x, p.point.y - anchor.y)
            if d < 90, d < (best?.distance ?? .infinity) { best = (i, d) }
        }
        guard let best else { return plane }
        return scene.nodes[best.index].position(atYears: t) - SIMD3(scene.fitCenter.x, scene.fitCenter.y, 0)
    }

    /// Tilts into 3D or back down to the flat map, keeping the middle where it is.
    private func setTilt(_ on: Bool) {
        var state = renderer.camera.state
        guard state.is3D != on else { return }
        state.tilt = on ? GraphCameraState.tilt3D : 0
        if on {
            // Swing round a little on the way in: the motion shows the depth.
            state.yaw += 0.45
            // Centre on the place's 3D middle, zoomed out enough to hold all of it.
            state.target.z = scene.fitDepth
            if let r = scene.fitRadius3D { state.zoom = min(state.zoom, scene.fitRadius / r) }
        } else {
            state.yaw = 0
            state.target.z = 0
        }
        beginMoving()
        renderer.camera.animate(to: state) { settle() }
    }

    /// Selects a node and moves it to the centre, zooming in if it's lost among its neighbours.
    private func focus(on index: Int, size: CGSize) {
        let node = scene.nodes[index]
        let p = node.position
        let nearest = scene.neighbors(of: index).map { simd_distance(scene.nodes[$0].position, p) }.min()
        var state = renderer.camera.state
        if let nearest, nearest > 0 {
            // At least ~60 points to the nearest linked neighbour.
            state.zoom = min(max(state.zoom, 60 / (nearest * baseScale(size))), GraphCameraState.maxZoom)
        }
        state.target = node.position(atYears: years) - SIMD3(scene.fitCenter.x, scene.fitCenter.y, 0)
        // Keep the 3D view, even if a focus arrives before the map has tilted.
        if is3D { state.tilt = max(state.tilt, GraphCameraState.tilt3D) }
        beginMoving()
        renderer.camera.animate(to: state) { settle() }
        withAnimation(.easeInOut(duration: 0.35)) { selected = index }
    }

    // MARK: Drawing

    private var here: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.69, blue: 0.36) : Color(red: 1.0, green: 0.48, blue: 0.10)
    }

    /// Names, worked out for where the map came to rest (hidden while it moves).
    private func drawLabels(in context: inout GraphicsContext, size: CGSize) {
        let points = screenPoints(rest, size: size)
        let highlight: Set<Int> = selected.map { scene.neighbors(of: $0).union([$0]) } ?? []
        drawLabels(in: &context, points: points, size: size, highlight: highlight)
    }

    private func drawLabels(in context: inout GraphicsContext, points: [CGPoint], size: CGSize, highlight: Set<Int>) {
        let screen = CGRect(origin: .zero, size: size)
        // Label where you are, the selection and its neighbours, and big named objects; skip catalog-number names.
        var order = scene.nodes.indices.filter { i in
            let n = scene.nodes[i]
            guard isVisible(i), screen.contains(points[i]) else { return false }
            if n.isHere || n.isLandmark || i == selected || highlight.contains(i) { return true }
            return n.size >= detailThreshold && !n.name.hasPrefix("PGC ") && !n.name.hasPrefix("HR ")
        }
        order.sort { a, b in
            let ra = labelRank(a, highlight: highlight), rb = labelRank(b, highlight: highlight)
            return ra != rb ? ra < rb : scene.nodes[a].size > scene.nodes[b].size
        }
        var taken: [CGRect] = []
        // Each label sits on a plate of the background color so links and dots don't run through it.
        let plate = Color(.systemBackground).opacity(0.78)
        for i in order.prefix(120) where taken.count < 28 {
            let n = scene.nodes[i]
            let r = dotRadius(n)
            let isAccent = n.isHere || i == selected
            let label = context.resolve(
                Text(n.name)
                    .font(.system(size: isAccent ? 12 : 10.5, weight: isAccent ? .semibold : .regular))
                    .foregroundColor(isAccent ? here : .secondary)
            )
            let s = label.measure(in: size)
            let p = points[i]
            // Start labels outside the orange rings around where you are and the selection.
            let gap: CGFloat = n.isHere ? 12 : (i == selected ? 6 : 0)
            let candidates = [
                CGRect(x: p.x + r + 5 + gap, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - r - 5 - gap - s.width, y: p.y - s.height / 2, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y - r - 3 - gap - s.height, width: s.width, height: s.height),
                CGRect(x: p.x - s.width / 2, y: p.y + r + 3 + gap, width: s.width, height: s.height),
            ]
            if let rect = candidates.first(where: { rect in screen.contains(rect) && !taken.contains { $0.intersects(rect) } }) {
                taken.append(rect.insetBy(dx: -7, dy: -3))
                context.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -1), cornerRadius: 4), with: .color(plate))
                context.draw(label, in: rect)
            }
        }
    }

    /// Lower ranks get labels first: where you are, the selection, its neighbours, then the rest.
    private func labelRank(_ i: Int, highlight: Set<Int>) -> Int {
        if i == selected { return 0 }
        if scene.nodes[i].isHere { return 1 }
        if highlight.contains(i) { return 2 }
        return scene.nodes[i].isMuted ? 4 : 3
    }

    // MARK: Overlays

    private func selectionCard(_ node: GraphNode) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(node.isHere ? .orange : .primary)
                Text(node.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let facts = node.facts {
                Button {
                    onFacts(facts)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)
                .accessibilityLabel("Facts about \(node.name)")
            }
            if let place = node.opens {
                Button("Open") { onOpen(place) }
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(14)
        .atlasGlass(RoundedRectangle(cornerRadius: 22))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var captionText: String {
        // Away from now, say what the motion is based on and what it leaves out.
        if let clock = timeClock, let motion = scene.motion, clock.isPlaying || abs(clock.years) >= 0.5 {
            return motion.isPrediction(clock.years) ? motion.predictionNote : motion.note
        }
        guard visible != nil, let shownCount else { return scene.caption }
        let total = scene.nodes.count - scene.nodes.filter(\.isHere).count
        return "Showing \(shownCount.formatted()) of \(total.formatted()) with the current filter. \(scene.caption)"
    }

    private func countShown() {
        guard let visible else { shownCount = nil; return }
        // Where you are always shows, so it isn't counted.
        shownCount = scene.nodes.indices.filter { !scene.nodes[$0].isHere && visible[$0] }.count
    }

    private func scaleBar(size: CGSize) -> some View {
        let unitsPerPoint = 1 / (baseScale(size) * rest.zoom)
        let length = Self.niceLength(unitsPerPoint * 90)
        let width = CGFloat(length / unitsPerPoint)
        let ly = GraphBuilder.lightYearsText(parsecs: length * scene.unit.parsecs)
        return VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color.secondary).frame(width: width, height: 1)
                .overlay(alignment: .leading) { Rectangle().fill(Color.secondary).frame(width: 1, height: 7) }
                .overlay(alignment: .trailing) { Rectangle().fill(Color.secondary).frame(width: 1, height: 7) }
            Text("\(length.formatted()) \(scene.unit.symbol) · \(ly)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
            Text(captionText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 1, 2 or 5 times a power of ten, at most `x`.
    private static func niceLength(_ x: Double) -> Double {
        let power = pow(10, floor(log10(x)))
        for m in [5.0, 2.0, 1.0] where m * power <= x { return m * power }
        return power
    }

    private func objectsPanel(size: CGSize) -> some View {
        // Sorting thousands of nodes is only worth it while the panel is open; the body reruns on
        // every pan and zoom frame.
        let ranked = !showObjects ? [] : scene.nodes.indices.filter(isVisible).sorted { a, b in
            let na = scene.nodes[a], nb = scene.nodes[b]
            if na.isHere != nb.isHere { return na.isHere }
            if na.isMuted != nb.isMuted { return !na.isMuted }
            return na.size > nb.size
        }
        return HStack(alignment: .top, spacing: 0) {
            if showObjects {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(ranked.count.formatted()) objects")
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

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(ranked.prefix(500), id: \.self) { i in
                                let n = scene.nodes[i]
                                Button {
                                    focus(on: i, size: size)
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(StarColor.swiftUI(temperature: n.temperatureK, dark: colorScheme == .dark)
                                                  .opacity(n.isMuted ? 0.5 : 1))
                                            .overlay(Circle().stroke(Color.orange, lineWidth: n.isHere || i == selected ? 1.5 : 0).padding(-2))
                                            .frame(width: 4 + 6 * n.size, height: 4 + 6 * n.size)
                                            .frame(width: 14)
                                        Text(n.name)
                                            .font(.system(size: 15))
                                            .foregroundColor(n.isHere || i == selected ? .orange : .primary)
                                            .lineLimit(1)
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
                .frame(width: 210)
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
}

/// A region's cells filled and blurred once, at a fixed resolution in layout units, so drawing it is
/// a single image instead of thousands of squares and a full-screen blur on every frame.
struct RegionImage {
    let image: CGImage
    /// Layout position of the image's top-left corner, and its size in layout units.
    let topLeft: SIMD2<Double>
    let size: SIMD2<Double>

    init?(_ region: (cells: [SIMD2<Double>], cellSize: Double)) {
        guard let first = region.cells.first else { return nil }
        var lo = first, hi = first
        for c in region.cells { lo = simd_min(lo, c); hi = simd_max(hi, c) }
        // Blurred by more than half a cell, as before, with room around it for the blur to fade out.
        let blur = region.cellSize * 0.65
        let margin = region.cellSize / 2 + blur * 3
        lo -= SIMD2(repeating: margin)
        hi += SIMD2(repeating: margin)
        let span = hi - lo
        let pixelsPerUnit = 1400 / max(span.x, span.y)
        let width = Int((span.x * pixelsPerUnit).rounded(.up)), height = Int((span.y * pixelsPerUnit).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let side = region.cellSize * pixelsPerUnit
        // Bitmap y runs up, like layout y, so the image comes out the right way up.
        for c in region.cells {
            context.fill(CGRect(x: (c.x - lo.x) * pixelsPerUnit - side / 2, y: (c.y - lo.y) * pixelsPerUnit - side / 2,
                                width: side + 0.5, height: side + 0.5))
        }
        guard let sharp = context.makeImage() else { return nil }
        let input = CIImage(cgImage: sharp)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: blur * pixelsPerUnit).cropped(to: input.extent)
        guard let image = CIContext().createCGImage(blurred, from: input.extent) else { return nil }
        self.image = image
        topLeft = SIMD2(lo.x, hi.y)
        size = span
    }
}
