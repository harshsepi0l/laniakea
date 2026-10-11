import simd
import SwiftUI

/// An Obsidian-style graph of real objects at their real positions seen from above: glowing dots,
/// links to neighbours, and selection that highlights a dot's links. Pinch to zoom, drag to pan,
/// tap a dot to select it, tap it again (or Open) to go inside, or tap the info button for its facts.
struct CosmicGraphView: View {
    let scene: GraphScene
    @Binding var focusID: String?
    /// Which nodes the filter shows; nil shows them all.
    var visible: [Bool]? = nil
    let onOpen: (AtlasPlace) -> Void
    let onFacts: (FactSubject) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var selected: Int?
    @State private var showObjects = false

    private static let maxZoom: CGFloat = 4000

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                // Fade the top edge so objects don't stop at a hard line under the filter row.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            let start = panStart ?? pan
                            panStart = start
                            pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                        }
                        .onEnded { _ in panStart = nil }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in zoomAround(value.startLocation, magnification: value.magnification, size: geo.size) }
                        .onEnded { _ in zoomStart = nil; panStart = nil }
                )

                objectsPanel(size: geo.size)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Spacer()
                    if let selected {
                        selectionCard(scene.nodes[selected])
                    }
                    scaleBar(size: geo.size)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(selected != nil)
            }
            .onChange(of: visible) { _, _ in
                if let selected, !isVisible(selected) { self.selected = nil }
            }
            .onChange(of: focusID) { _, id in
                guard let id, let index = scene.nodes.firstIndex(where: { $0.id == id }) else { return }
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

    private func screenPoint(_ p: SIMD2<Double>, size: CGSize, scale: Double) -> CGPoint {
        CGPoint(
            x: size.width / 2 + CGFloat((p.x - scene.fitCenter.x) * scale) + pan.width,
            y: size.height / 2 - CGFloat((p.y - scene.fitCenter.y) * scale) + pan.height
        )
    }

    /// Small for most objects so thousands stay legible; grows a little as you zoom in.
    private func dotRadius(_ node: GraphNode) -> CGFloat {
        (0.7 + 4.6 * CGFloat(pow(node.size, 1.6))) * min(pow(zoom, 0.35), 3)
    }

    /// Below this size a node is drawn faint and unlabeled; it falls as you zoom in.
    private var detailThreshold: Double { 0.42 / Double(pow(zoom, 0.5)) }

    private func isVisible(_ i: Int) -> Bool { visible?[i] ?? true }

    private func node(at point: CGPoint, size: CGSize) -> Int? {
        let scale = baseScale(size) * Double(zoom)
        var best: (Int, CGFloat)?
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            let p = screenPoint(n.position, size: size, scale: scale)
            let d = hypot(p.x - point.x, p.y - point.y) + (n.size < detailThreshold ? 6 : 0)
            if d < max(22, dotRadius(n) + 8), d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func zoomAround(_ anchor: CGPoint, magnification: CGFloat, size: CGSize) {
        let startZoom = zoomStart ?? zoom
        let startPan = panStart ?? pan
        zoomStart = startZoom
        panStart = startPan
        let newZoom = min(max(startZoom * magnification, 0.5), Self.maxZoom)
        let ratio = newZoom / startZoom
        let cx = size.width / 2, cy = size.height / 2
        zoom = newZoom
        pan = CGSize(
            width: anchor.x - cx - (anchor.x - cx - startPan.width) * ratio,
            height: anchor.y - cy - (anchor.y - cy - startPan.height) * ratio
        )
    }

    /// Selects a node and moves it to the centre, zooming in if it's lost among its neighbours.
    private func focus(on index: Int, size: CGSize) {
        let p = scene.nodes[index].position
        let nearest = scene.neighbors(of: index).map { simd_distance(scene.nodes[$0].position, p) }.min()
        var target = zoom
        if let nearest, nearest > 0 {
            // At least ~60 points to the nearest linked neighbour.
            target = min(max(zoom, CGFloat(60 / (nearest * baseScale(size)))), Self.maxZoom)
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            zoom = target
            let scale = baseScale(size) * Double(target)
            pan = CGSize(width: -CGFloat((p.x - scene.fitCenter.x) * scale), height: CGFloat((p.y - scene.fitCenter.y) * scale))
            selected = index
        }
    }

    // MARK: Drawing

    private var ink: Color { colorScheme == .dark ? .white : Color(white: 0.07) }
    /// Objects whose color hasn't been measured.
    private var unknown: Color { Color(white: colorScheme == .dark ? 0.62 : 0.42) }
    private var here: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.69, blue: 0.36) : Color(red: 1.0, green: 0.48, blue: 0.10)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let dark = colorScheme == .dark
        let scale = baseScale(size) * Double(zoom)
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
        let points = scene.nodes.map { screenPoint($0.position, size: size, scale: scale) }
        let highlight: Set<Int> = selected.map { scene.neighbors(of: $0).union([$0]) } ?? []

        // Region (Laniakea's outline): the union of its cells, filled once so overlaps don't darken.
        if let region = scene.region {
            var path = Path()
            let side = CGFloat(region.cellSize * scale)
            for cell in region.cells {
                let c = screenPoint(cell, size: size, scale: scale)
                path.addRect(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side + 0.5, height: side + 0.5))
            }
            // Blurred by more than half a cell so the 10 Mpc cells read as one soft shape, not steps.
            var soft = context
            soft.addFilter(.blur(radius: max(side * 0.65, 2)))
            soft.fill(path, with: .color(here.opacity(dark ? 0.13 : 0.12)))
        }

        // Links.
        var links = Path()
        var lit = Path()
        for (a, b) in scene.links where isVisible(a) && isVisible(b) {
            let pa = points[a], pb = points[b]
            guard bounds.contains(pa) || bounds.contains(pb) else { continue }
            if let selected, a == selected || b == selected {
                lit.move(to: pa); lit.addLine(to: pb)
            } else {
                links.move(to: pa); links.addLine(to: pb)
            }
        }
        context.stroke(links, with: .color(ink.opacity((dark ? 0.11 : 0.09) * (selected == nil ? 1 : 0.5))), lineWidth: 0.6)
        context.stroke(lit, with: .color(here.opacity(0.8)), lineWidth: 1.3)

        // Dots, batched by color bin and style. Every star, galaxy and group takes its color from the
        // shared star color scale; objects with no measured color are grey. Where you are and the
        // selection keep their color and get an orange ring.
        enum Style: Int { case normal, faint, muted, dimmed }
        var batches: [Int?: [Style: Path]] = [:]
        var rings = Path(), homeRings = Path(), plainAccent = Path()
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            let p = points[i]
            guard bounds.contains(p) else { continue }
            let r = dotRadius(n)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let isAccent = n.isHere || i == selected
            let bin = n.temperatureK.map { StarColor.bin(temperature: $0) }
            let color = bin.map { StarColor.color(bin: $0).color(dark: dark) } ?? unknown
            if isAccent || n.size > 0.55 {
                let glow = r * 3.4
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: glow * 2, height: glow * 2)),
                    with: .radialGradient(Gradient(colors: [color.opacity(isAccent ? 0.45 : (dark ? 0.24 : 0.14)), color.opacity(0)]),
                                          center: p, startRadius: 0, endRadius: glow)
                )
            }
            if isAccent {
                // Where you are gets a wider double ring so it stands out in dense fields.
                if n.isHere {
                    homeRings.addEllipse(in: rect.insetBy(dx: -4, dy: -4))
                    homeRings.addEllipse(in: rect.insetBy(dx: -9, dy: -9))
                } else {
                    rings.addEllipse(in: rect.insetBy(dx: -3, dy: -3))
                }
                if bin == nil { plainAccent.addEllipse(in: rect) } else { batches[bin, default: [:]][.normal, default: Path()].addEllipse(in: rect) }
                continue
            }
            let style: Style = selected != nil && !highlight.contains(i) ? .dimmed
                : n.isMuted ? .muted
                : n.size < detailThreshold && !highlight.contains(i) ? .faint : .normal
            batches[bin, default: [:]][style, default: Path()].addEllipse(in: rect)
        }
        let opacity: [Style: Double] = [.normal: 1, .faint: 0.6, .muted: 0.32, .dimmed: 0.2]
        for (bin, styles) in batches {
            let color = bin.map { StarColor.color(bin: $0).color(dark: dark) } ?? unknown
            for (style, path) in styles.sorted(by: { $0.key.rawValue > $1.key.rawValue }) {
                context.fill(path, with: .color(color.opacity(opacity[style] ?? 1)))
            }
        }
        context.fill(plainAccent, with: .color(here))
        context.stroke(rings, with: .color(here), lineWidth: 1.6)
        // A background-colored band under the rings separates them from red and orange stars nearby.
        context.stroke(homeRings, with: .color(Color(.systemBackground).opacity(0.85)), lineWidth: 5)
        context.stroke(homeRings, with: .color(here), lineWidth: 2)

        drawLabels(in: &context, points: points, size: size, highlight: highlight)
    }

    private func drawLabels(in context: inout GraphicsContext, points: [CGPoint], size: CGSize, highlight: Set<Int>) {
        let screen = CGRect(origin: .zero, size: size)
        // Label where you are, the selection and its neighbours, and big named objects; skip catalog-number names.
        var order = scene.nodes.indices.filter { i in
            let n = scene.nodes[i]
            guard isVisible(i), screen.contains(points[i]) else { return false }
            if n.isHere || i == selected || highlight.contains(i) { return true }
            return n.size >= detailThreshold && !n.name.hasPrefix("PGC ")
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
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var captionText: String {
        guard let visible else { return scene.caption }
        // Where you are always shows, so it isn't counted.
        let objects = scene.nodes.indices.filter { !scene.nodes[$0].isHere }
        let shown = objects.filter { visible[$0] }.count
        return "Showing \(shown.formatted()) of \(objects.count.formatted()) with the current filter. \(scene.caption)"
    }

    private func scaleBar(size: CGSize) -> some View {
        let unitsPerPoint = 1 / (baseScale(size) * Double(zoom))
        let length = Self.niceLength(unitsPerPoint * 90)
        let width = CGFloat(length / unitsPerPoint)
        let ly = GraphBuilder.lightYearsText(parsecs: length * (scene.unit == .megaparsecs ? 1e6 : 1))
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
