import Combine
import MetalKit
import simd
import SwiftUI

/// Draws a `GraphScene` with Metal (shaders in GraphShaders.swift): Laniakea's fill and edge, the links, and every object's glow,
/// dot and ring. The objects are uploaded once and redrawn only when what's shown or selected
/// changes; a frame is a handful of draw calls whatever the number of objects.
final class GraphRenderer: NSObject, MTKViewDelegate {
    /// What the map shows. The renderer rebuilds its buffers when this changes.
    struct Content {
        let scene: GraphScene
        let visible: [Bool]?
        let selected: Int?
        let dark: Bool
        let regionImage: RegionImage?
        /// Runs time in places with measured motion; nil keeps everything where it is now.
        let clock: DeepTimeClock?
        var overlays = Overlays()
    }

    /// Layers drawn behind the objects, each switched in Settings.
    struct Overlays: Equatable {
        var flow = true
        var web = true
        var boundary = true
    }
    private var overlays = Overlays()

    let camera = GraphCamera()
    private weak var clock: DeepTimeClock?
    /// Play, pause and Now come straight from the clock: SwiftUI doesn't update this view for them,
    /// since nothing it's given changes.
    private var clockWatch: AnyCancellable?

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var spritePipeline: MTLRenderPipelineState?
    private var segmentPipeline: MTLRenderPipelineState?
    private var regionPipeline: MTLRenderPipelineState?

    private var scene: GraphScene?
    private var key: Key?
    private var sprites: MTLBuffer?, spriteCount = 0
    private var links: MTLBuffer?, linkCount = 0
    private var edges: MTLBuffer?, edgeCount = 0
    private var contours: MTLBuffer?, contourCount = 0
    /// Cosmic flow lines and web: in 3D through the region, and flat in the layout plane.
    private var flow: MTLBuffer?, flowCount = 0
    private var planeFlow: MTLBuffer?, planeFlowCount = 0
    private var web: MTLBuffer?, webCount = 0
    private var planeWeb: MTLBuffer?, planeWebCount = 0
    private var regionTexture: MTLTexture?
    private var regionQuad: RegionQuadData?

    private struct Key: Equatable {
        let visible: [Bool]?
        let selected: Int?
        let dark: Bool
        let hasRegionImage: Bool
    }

    // MARK: Setup

    func makeView() -> MTKView {
        let view = MTKView()
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        // Only draws when asked (a gesture, an animation, new content).
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = self
        camera.view = view
        if let device { buildPipelines(device: device, format: view.colorPixelFormat) }
        queue = device?.makeCommandQueue()
        return view
    }

    private func buildPipelines(device: MTLDevice, format: MTLPixelFormat) {
        guard let library = GraphShaders.library(device: device) else { return }
        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            let c = d.colorAttachments[0]!
            c.pixelFormat = format
            // Premultiplied alpha, drawn over what's already there.
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        spritePipeline = pipeline("spriteVertex", "spriteFragment")
        segmentPipeline = pipeline("segmentVertex", "segmentFragment")
        regionPipeline = pipeline("regionVertex", "regionFragment")
    }

    // MARK: Content

    func update(_ content: Content) {
        scene = content.scene
        if overlays != content.overlays {
            overlays = content.overlays
            camera.changed()
        }
        if content.clock !== clock {
            clock = content.clock
            clockWatch = content.clock?.objectWillChange.sink { [weak self] _ in
                // objectWillChange fires before the change lands, so read it on the next turn.
                DispatchQueue.main.async { self?.clockChanged() }
            }
        }
        clockChanged()
        let newKey = Key(visible: content.visible, selected: content.selected, dark: content.dark,
                         hasRegionImage: content.regionImage != nil)
        guard newKey != key, let device else { return }
        key = newKey
        build(content, device: device)
        camera.changed()
    }

    /// Draws every frame while time runs, and once more when it stops or jumps back to now.
    private func clockChanged() {
        camera.isTimeRunning = clock?.isPlaying ?? false
        camera.changed()
    }

    private func build(_ content: Content, device: MTLDevice) {
        let scene = content.scene
        let dark = content.dark
        let palette = Palette(dark: dark)
        func isVisible(_ i: Int) -> Bool { content.visible?[i] ?? true }
        // Positions relative to the fit centre keep single-precision floats accurate when zoomed in.
        func position(_ p: SIMD2<Double>, depth: Double = 0) -> SIMD3<Float> {
            SIMD3(Float(p.x - scene.fitCenter.x), Float(p.y - scene.fitCenter.y), Float(depth))
        }
        func velocity(_ v: SIMD3<Double>?) -> SIMD3<Float> {
            guard let v else { return .zero }
            return SIMD3(Float(v.x), Float(v.y), Float(v.z))
        }
        // Laniakea's edge grows with the expansion of space, about the Milky Way.
        func expansion(_ p: SIMD2<Double>) -> SIMD3<Float> {
            SIMD3(Float(p.x), Float(p.y), 0) * Float(scene.regionExpansionPerYear)
        }
        let selected = content.selected
        let highlight: Set<Int> = selected.map { scene.neighbors(of: $0).union([$0]) } ?? []

        // Laniakea's fill, from the pre-blurred image.
        if let image = content.regionImage {
            regionTexture = try? MTKTextureLoader(device: device).newTexture(cgImage: image.image, options: [.SRGB: false])
            let tl = image.topLeft, s = image.size
            let corners = [SIMD2(tl.x, tl.y), SIMD2(tl.x + s.x, tl.y), SIMD2(tl.x, tl.y - s.y), SIMD2(tl.x + s.x, tl.y - s.y)]
            regionQuad = RegionQuadData(
                color: palette.here.withAlpha(dark ? 0.13 : 0.12),
                c0: SIMD4(position(corners[0]), 1), c1: SIMD4(position(corners[1]), 1),
                c2: SIMD4(position(corners[2]), 1), c3: SIMD4(position(corners[3]), 1)
            )
        } else {
            regionTexture = nil
            regionQuad = nil
        }

        // Laniakea's edge: a soft orange glow under a crisp line.
        var edgeSegments: [SegmentData] = []
        for (a, b) in scene.regionOutline {
            edgeSegments.append(SegmentData(color: palette.here.withAlpha(0.4), a: position(a), b: position(b),
                                            velocityA: expansion(a), velocityB: expansion(b), width: 9, soft: 1))
        }
        for (a, b) in scene.regionOutline {
            edgeSegments.append(SegmentData(color: palette.here.withAlpha(0.9), a: position(a), b: position(b),
                                            velocityA: expansion(a), velocityB: expansion(b), width: 1.4, soft: 0))
        }
        (edges, edgeCount) = buffer(edgeSegments, device: device)

        // The same region's true shape in 3D: a ring around its edge at every layer of cells.
        func position3(_ p: SIMD3<Double>) -> SIMD3<Float> {
            SIMD3(Float(p.x - scene.fitCenter.x), Float(p.y - scene.fitCenter.y), Float(p.z))
        }
        func expansion3(_ p: SIMD3<Double>) -> SIMD3<Float> {
            SIMD3(Float(p.x), Float(p.y), Float(p.z)) * Float(scene.regionExpansionPerYear)
        }
        (contours, contourCount) = buffer(scene.regionContours.map { a, b in
            SegmentData(color: palette.here.withAlpha(0.3), a: position3(a), b: position3(b),
                        velocityA: expansion3(a), velocityB: expansion3(b), width: 1, soft: 0)
        }, device: device)

        // How matter flows: each line brightens downstream, so the direction reads at a glance, then
        // fades just before it ends, where hundreds of lines meet at an attractor.
        func flowSegments(_ lines: [[SIMD3<Double>]]) -> [SegmentData] {
            var out: [SegmentData] = []
            for full in lines where full.count > 1 {
                // Every other point: the lines stay smooth at half the drawing.
                var line = Swift.stride(from: 0, to: full.count, by: 2).map { full[$0] }
                if line.last != full.last, let last = full.last { line.append(last) }
                guard line.count > 1 else { continue }
                for k in 1..<line.count {
                    let t = Float(k) / Float(line.count - 1)
                    let alpha = (0.04 + 0.22 * t) * min(1, (1 - t) / 0.25 + 0.05)
                    let a = line[k - 1], b = line[k]
                    out.append(SegmentData(color: palette.ink.withAlpha(alpha), a: position3(a), b: position3(b),
                                           velocityA: expansion3(a), velocityB: expansion3(b), width: 0.8, soft: 0))
                }
            }
            return out
        }
        (flow, flowCount) = buffer(flowSegments(scene.flowLines), device: device)
        (planeFlow, planeFlowCount) = buffer(flowSegments(scene.planeFlowLines), device: device)

        // The cosmic web: a soft point in each dense region, bigger and brighter where it's denser.
        let webColor = dark ? SIMD4<Float>(1, 0.86, 0.72, 1) : palette.here
        func webSprites(_ cells: [(position: SIMD3<Double>, density: Double)]) -> [SpriteData] {
            cells.map { cell in
                let d = Float(cell.density)
                return SpriteData(color: webColor.withAlpha(min(0.12 + 0.06 * d, 0.32)),
                                  position: position3(cell.position), velocity: expansion3(cell.position),
                                  size: min(0.15 + 0.08 * d, 0.45), shape: 1, extra: 2.6)
            }
        }
        (web, webCount) = buffer(webSprites(scene.web), device: device)
        (planeWeb, planeWebCount) = buffer(webSprites(scene.planeWeb), device: device)

        // Links, with the selection's drawn on top in orange.
        var plain: [SegmentData] = [], lit: [SegmentData] = []
        let linkColor = palette.ink.withAlpha(Float((dark ? 0.11 : 0.09) * (selected == nil ? 1 : 0.5)))
        for (a, b) in scene.links where isVisible(a) && isVisible(b) {
            let na = scene.nodes[a], nb = scene.nodes[b]
            let pa = position(na.position, depth: na.depth), pb = position(nb.position, depth: nb.depth)
            let va = velocity(na.velocity), vb = velocity(nb.velocity)
            if let selected, a == selected || b == selected {
                lit.append(SegmentData(color: palette.here.withAlpha(0.8), a: pa, b: pb, velocityA: va, velocityB: vb, width: 1.3, soft: 0))
            } else {
                plain.append(SegmentData(color: linkColor, a: pa, b: pb, velocityA: va, velocityB: vb, width: 0.6, soft: 0))
            }
        }
        (links, linkCount) = buffer(plain + lit, device: device)

        // Glows, then dots from faintest to brightest, then where you are and the selection with
        // their rings on top. Every object takes its color from the shared star color scale;
        // objects with no measured color are grey.
        var glows: [SpriteData] = [], dimmed: [SpriteData] = [], muted: [SpriteData] = [], normal: [SpriteData] = []
        var accents: [SpriteData] = [], rings: [SpriteData] = []
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            let p = position(n.position, depth: n.depth)
            let v = velocity(n.velocity)
            let size = Float(n.size)
            let isAccent = n.isHere || i == selected
            let color = n.temperatureK.map { palette.star(temperature: $0) } ?? palette.unknown
            if n.isBlackHole {
                // Its own look, drawn over the stars around it, with an orange ring like any pick
                // when selected.
                accents.append(SpriteData(color: SIMD4(1, 1, 1, selected != nil && !highlight.contains(i) ? 0.35 : 1),
                                         position: p, velocity: v, size: max(size, 0.5), shape: 4, extra: 6.5))
                if isAccent {
                    rings.append(SpriteData(color: palette.here, position: p, velocity: v, size: max(size, 0.5), shape: 2, extra: 22, width: 1.6))
                }
                continue
            }
            if isAccent || n.size > 0.55 {
                glows.append(SpriteData(color: color.withAlpha(isAccent ? 0.45 : (dark ? 0.24 : 0.14)), position: p, velocity: v, size: size, shape: 1, extra: 3.4))
            }
            if isAccent {
                accents.append(SpriteData(color: n.temperatureK == nil ? palette.here : color, position: p, velocity: v, size: size))
                if n.isHere {
                    // Where you are gets a wider double ring on a background-colored band, so it
                    // stands out from red and orange stars nearby.
                    for extra: Float in [4, 9] {
                        rings.append(SpriteData(color: palette.background.withAlpha(0.85), position: p, velocity: v, size: size, shape: 2, extra: extra, width: 5))
                    }
                    for extra: Float in [4, 9] {
                        rings.append(SpriteData(color: palette.here, position: p, velocity: v, size: size, shape: 2, extra: extra, width: 2))
                    }
                } else {
                    rings.append(SpriteData(color: palette.here, position: p, velocity: v, size: size, shape: 2, extra: 3, width: 1.6))
                }
                continue
            }
            if selected != nil && !highlight.contains(i) {
                dimmed.append(SpriteData(color: color.withAlpha(0.2), position: p, velocity: v, size: size))
            } else if n.isMuted {
                muted.append(SpriteData(color: color.withAlpha(0.32), position: p, velocity: v, size: size))
            } else {
                normal.append(SpriteData(color: color, position: p, velocity: v, size: size, faintable: highlight.contains(i) ? 0 : 1))
            }
        }
        (sprites, spriteCount) = buffer(glows + dimmed + muted + normal + accents + rings, device: device)
    }

    private func buffer<T>(_ items: [T], device: MTLDevice) -> (MTLBuffer?, Int) {
        guard !items.isEmpty else { return (nil, 0) }
        let buffer = items.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
        return (buffer, items.count)
    }

    // MARK: Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let completion = camera.step(now: now)
        defer { completion?() }
        if let clock, let motion = scene?.motion { clock.tick(now: now, motion: motion) }
        guard let scene, let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let size = view.bounds.size
        var uniforms = uniforms(scene: scene, size: size, drawable: view.drawableSize, scale: view.contentScaleFactor)

        // Laniakea's shading and edge are a flat slice through it, so they fade out as the map tilts
        // into 3D rather than float there as a sheet.
        let flatness = Float(max(0, 1 - camera.state.tilt / 0.35))
        let boundary: Float = overlays.boundary ? 1 : 0
        let flowShown: Float = overlays.flow ? 1 : 0
        let webShown: Float = overlays.web ? 1 : 0
        if let regionPipeline, let regionTexture, var quad = regionQuad, flatness > 0, overlays.boundary {
            quad.color.w *= flatness
            encoder.setRenderPipelineState(regionPipeline)
            encoder.setVertexBytes(&quad, length: MemoryLayout<RegionQuadData>.stride, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformsData>.stride, index: 1)
            encoder.setFragmentBytes(&quad, length: MemoryLayout<RegionQuadData>.stride, index: 0)
            encoder.setFragmentTexture(regionTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if let segmentPipeline {
            encoder.setRenderPipelineState(segmentPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformsData>.stride, index: 1)
            // Links join today's nearest neighbours; as time runs those pairs drift apart, so the
            // links fade out over half the place's reliable range. Laniakea's edge stays.
            var linkOpacity: Float = 1
            if let clock, let motion = scene.motion {
                linkOpacity = Float(max(0, 1 - abs(clock.years) / (motion.reliableYears * 0.5)))
            }
            for (buffer, count, opacity) in [(edges, edgeCount, flatness * boundary), (contours, contourCount, (1 - flatness) * boundary),
                                             (planeFlow, planeFlowCount, flatness * flowShown), (flow, flowCount, (1 - flatness) * flowShown),
                                             (links, linkCount, linkOpacity)] {
                guard let buffer, count > 0, opacity > 0 else { continue }
                var opacity = opacity
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&opacity, length: MemoryLayout<Float>.stride, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
        }
        if let spritePipeline {
            encoder.setRenderPipelineState(spritePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformsData>.stride, index: 1)
            // The web under everything else, then the objects.
            for (buffer, count, opacity) in [(planeWeb, planeWebCount, flatness * webShown), (web, webCount, (1 - flatness) * webShown),
                                             (sprites, spriteCount, Float(1))] {
                guard let buffer, count > 0, opacity > 0 else { continue }
                var opacity = opacity
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&opacity, length: MemoryLayout<Float>.stride, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// The camera's projection (the same one names and taps use) and the time, for the shaders.
    private func uniforms(scene: GraphScene, size: CGSize, drawable: CGSize, scale: CGFloat) -> UniformsData {
        let projection = GraphProjection(scene: scene, state: camera.state, size: size)
        let zoom = camera.state.zoom
        return UniformsData(
            worldToClip: projection.worldToClip,
            viewport: SIMD2(Float(drawable.width), Float(drawable.height)),
            pixelsPerPoint: Float(scale),
            zoom: Float(zoom),
            detailThreshold: Float(0.42 / zoom.squareRoot()),
            time: Float(clock?.years ?? 0),
            perspective: Float(projection.distance ?? 0),
            expansion: Float(scene.regionExpansionPerYear),
            expansionOrigin: SIMD3(Float(-scene.fitCenter.x), Float(-scene.fitCenter.y), 0)
        )
    }
}

/// Hosts the renderer's Metal view in SwiftUI.
struct GraphMetalView: UIViewRepresentable {
    let renderer: GraphRenderer
    let content: GraphRenderer.Content

    func makeUIView(context: Context) -> MTKView {
        let view = renderer.makeView()
        renderer.update(content)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        renderer.update(content)
    }
}

// MARK: GPU data (must match the structs in GraphShaders.swift)

private struct UniformsData {
    var worldToClip: simd_float4x4
    var viewport: SIMD2<Float>
    var pixelsPerPoint: Float
    var zoom: Float
    var detailThreshold: Float
    var time: Float
    var perspective: Float
    var expansion: Float
    var expansionOrigin: SIMD3<Float>
}

private struct SpriteData {
    var color: SIMD4<Float>
    var position: SIMD3<Float>
    var velocity: SIMD3<Float> = .zero
    var size: Float
    var shape: Float = 0
    var extra: Float = 0
    var width: Float = 0
    var faintable: Float = 0
}

private struct SegmentData {
    var color: SIMD4<Float>
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var velocityA: SIMD3<Float>
    var velocityB: SIMD3<Float>
    var width: Float
    var soft: Float
}

private struct RegionQuadData {
    var color: SIMD4<Float>
    var c0: SIMD4<Float>, c1: SIMD4<Float>, c2: SIMD4<Float>, c3: SIMD4<Float>
}

/// The map's colors as straight-alpha RGBA, matching the SwiftUI colors they stand in for.
private struct Palette {
    let dark: Bool
    let here: SIMD4<Float>
    let ink: SIMD4<Float>
    let unknown: SIMD4<Float>
    let background: SIMD4<Float>
    private let bins: [SIMD4<Float>]

    init(dark: Bool) {
        self.dark = dark
        here = dark ? SIMD4(1.0, 0.69, 0.36, 1) : SIMD4(1.0, 0.48, 0.10, 1)
        ink = dark ? SIMD4(1, 1, 1, 1) : SIMD4(0.07, 0.07, 0.07, 1)
        let grey: Float = dark ? 0.62 : 0.42
        unknown = SIMD4(grey, grey, grey, 1)
        let style = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        background = Self.rgba(UIColor.systemBackground.resolvedColor(with: style))
        // As StarColor.RGB.color(dark:) shades them for each theme.
        bins = (0...StarColor.binEdges.count).map { bin in
            let c = StarColor.color(bin: bin)
            return dark ? SIMD4(Float(c.r), Float(c.g), Float(c.b), 1)
                : SIMD4(Float(c.r * 0.78), Float(c.g * 0.72), Float(c.b * 0.72), 1)
        }
    }

    func star(temperature: Double) -> SIMD4<Float> {
        let bin = StarColor.bin(temperature: temperature)
        return bins.indices.contains(bin) ? bins[bin] : unknown
    }

    private static func rgba(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}

private extension SIMD4 where Scalar == Float {
    func withAlpha(_ alpha: Float) -> SIMD4<Float> { SIMD4(x, y, z, w * alpha) }
    func withAlpha(_ alpha: Double) -> SIMD4<Float> { withAlpha(Float(alpha)) }
}
