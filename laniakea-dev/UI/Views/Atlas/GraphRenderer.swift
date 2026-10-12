import MetalKit
import simd
import SwiftUI

/// Where the map's camera is: a zoom and a pan in points, like the SwiftUI drawing used. Gestures
/// change it directly and ask for a redraw, without going through SwiftUI state, so moving the map
/// never rebuilds any views.
final class GraphCamera {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// Where a drag or pinch began.
    var zoomStart: CGFloat?
    var panStart: CGSize?

    fileprivate struct Animation {
        let fromZoom: CGFloat, fromPan: CGSize
        let toZoom: CGFloat, toPan: CGSize
        let start: CFTimeInterval, duration: CFTimeInterval
        let completion: () -> Void
    }
    fileprivate var animation: Animation?
    fileprivate weak var view: MTKView?

    var isAnimating: Bool { animation != nil }

    func changed() {
        view?.setNeedsDisplay()
    }

    /// Glides to a zoom and pan with an ease in and out, then calls `completion`.
    func animate(toZoom zoom: CGFloat, pan: CGSize, duration: CFTimeInterval = 0.35, completion: @escaping () -> Void) {
        animation = Animation(fromZoom: self.zoom, fromPan: self.pan, toZoom: zoom, toPan: pan,
                              start: CACurrentMediaTime(), duration: duration, completion: completion)
        // Draw every frame until it lands.
        view?.enableSetNeedsDisplay = false
        view?.isPaused = false
    }

    /// Moves the animation on to now; returns its completion once it's done.
    fileprivate func step(now: CFTimeInterval) -> (() -> Void)? {
        guard let a = animation else { return nil }
        let t = min(max((now - a.start) / a.duration, 0), 1)
        let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
        zoom = a.fromZoom + (a.toZoom - a.fromZoom) * e
        pan = CGSize(width: a.fromPan.width + (a.toPan.width - a.fromPan.width) * e,
                     height: a.fromPan.height + (a.toPan.height - a.fromPan.height) * e)
        guard t >= 1 else { return nil }
        animation = nil
        view?.isPaused = true
        view?.enableSetNeedsDisplay = true
        return a.completion
    }
}

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
    }

    let camera = GraphCamera()

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
        let newKey = Key(visible: content.visible, selected: content.selected, dark: content.dark,
                         hasRegionImage: content.regionImage != nil)
        guard newKey != key, let device else { return }
        key = newKey
        build(content, device: device)
        camera.changed()
    }

    private func build(_ content: Content, device: MTLDevice) {
        let scene = content.scene
        let dark = content.dark
        let palette = Palette(dark: dark)
        func isVisible(_ i: Int) -> Bool { content.visible?[i] ?? true }
        // Positions relative to the fit centre keep single-precision floats accurate when zoomed in.
        func position(_ p: SIMD2<Double>) -> SIMD3<Float> {
            SIMD3(Float(p.x - scene.fitCenter.x), Float(p.y - scene.fitCenter.y), 0)
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
            edgeSegments.append(SegmentData(color: palette.here.withAlpha(0.4), a: position(a), b: position(b), width: 9, soft: 1))
        }
        for (a, b) in scene.regionOutline {
            edgeSegments.append(SegmentData(color: palette.here.withAlpha(0.9), a: position(a), b: position(b), width: 1.4, soft: 0))
        }
        (edges, edgeCount) = buffer(edgeSegments, device: device)

        // Links, with the selection's drawn on top in orange.
        var plain: [SegmentData] = [], lit: [SegmentData] = []
        let linkColor = palette.ink.withAlpha(Float((dark ? 0.11 : 0.09) * (selected == nil ? 1 : 0.5)))
        for (a, b) in scene.links where isVisible(a) && isVisible(b) {
            let pa = position(scene.nodes[a].position), pb = position(scene.nodes[b].position)
            if let selected, a == selected || b == selected {
                lit.append(SegmentData(color: palette.here.withAlpha(0.8), a: pa, b: pb, width: 1.3, soft: 0))
            } else {
                plain.append(SegmentData(color: linkColor, a: pa, b: pb, width: 0.6, soft: 0))
            }
        }
        (links, linkCount) = buffer(plain + lit, device: device)

        // Glows, then dots from faintest to brightest, then where you are and the selection with
        // their rings on top. Every object takes its color from the shared star color scale;
        // objects with no measured color are grey.
        var glows: [SpriteData] = [], dimmed: [SpriteData] = [], muted: [SpriteData] = [], normal: [SpriteData] = []
        var accents: [SpriteData] = [], rings: [SpriteData] = []
        for (i, n) in scene.nodes.enumerated() where isVisible(i) {
            let p = position(n.position)
            let size = Float(n.size)
            let isAccent = n.isHere || i == selected
            let color = n.temperatureK.map { palette.star(temperature: $0) } ?? palette.unknown
            if isAccent || n.size > 0.55 {
                glows.append(SpriteData(color: color.withAlpha(isAccent ? 0.45 : (dark ? 0.24 : 0.14)), position: p, size: size, shape: 1, extra: 3.4))
            }
            if isAccent {
                accents.append(SpriteData(color: n.temperatureK == nil ? palette.here : color, position: p, size: size))
                if n.isHere {
                    // Where you are gets a wider double ring on a background-colored band, so it
                    // stands out from red and orange stars nearby.
                    for extra: Float in [4, 9] {
                        rings.append(SpriteData(color: palette.background.withAlpha(0.85), position: p, size: size, shape: 2, extra: extra, width: 5))
                    }
                    for extra: Float in [4, 9] {
                        rings.append(SpriteData(color: palette.here, position: p, size: size, shape: 2, extra: extra, width: 2))
                    }
                } else {
                    rings.append(SpriteData(color: palette.here, position: p, size: size, shape: 2, extra: 3, width: 1.6))
                }
                continue
            }
            if selected != nil && !highlight.contains(i) {
                dimmed.append(SpriteData(color: color.withAlpha(0.2), position: p, size: size))
            } else if n.isMuted {
                muted.append(SpriteData(color: color.withAlpha(0.32), position: p, size: size))
            } else {
                normal.append(SpriteData(color: color, position: p, size: size, faintable: highlight.contains(i) ? 0 : 1))
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
        let completion = camera.step(now: CACurrentMediaTime())
        defer { completion?() }
        guard let scene, let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let size = view.bounds.size
        var uniforms = uniforms(scene: scene, size: size, drawable: view.drawableSize, scale: view.contentScaleFactor)

        if let regionPipeline, let regionTexture, var quad = regionQuad {
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
            for (buffer, count) in [(edges, edgeCount), (links, linkCount)] {
                guard let buffer, count > 0 else { continue }
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
        }
        if let spritePipeline, let sprites, spriteCount > 0 {
            encoder.setRenderPipelineState(spritePipeline)
            encoder.setVertexBuffer(sprites, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformsData>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: spriteCount)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Layout coordinates (relative to the fit centre) to clip space, the same mapping as
    /// `CosmicGraphView.screenPoint`: y up in layout, down on screen, then the pan in points.
    private func uniforms(scene: GraphScene, size: CGSize, drawable: CGSize, scale: CGFloat) -> UniformsData {
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        let base = Double(min(size.width, size.height)) / 2 * 0.92 / scene.fitRadius
        let s = Float(base * Double(camera.zoom))
        let panX = Float(camera.pan.width), panY = Float(camera.pan.height)
        let worldToClip = simd_float4x4(columns: (
            SIMD4(2 * s / w, 0, 0, 0),
            SIMD4(0, 2 * s / h, 0, 0),
            SIMD4(0, 0, 0, 0),
            SIMD4(2 * panX / w, -2 * panY / h, 0.5, 1)
        ))
        return UniformsData(
            worldToClip: worldToClip,
            viewport: SIMD2(Float(drawable.width), Float(drawable.height)),
            pixelsPerPoint: Float(scale),
            zoom: Float(camera.zoom),
            detailThreshold: Float(0.42 / Double(pow(camera.zoom, 0.5)))
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
}

private struct SpriteData {
    var color: SIMD4<Float>
    var position: SIMD3<Float>
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
