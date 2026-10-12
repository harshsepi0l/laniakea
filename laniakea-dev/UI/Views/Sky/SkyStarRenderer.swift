import MetalKit
import simd
import SwiftUI

/// Draws the sky view's naked-eye stars with Metal. Their directions go to the GPU once; each frame
/// is one matrix (the sky's turn to your horizon, then where the camera points) and one draw call,
/// so following the device at 60 frames a second costs next to nothing. Planets, the Sun, names and
/// the reticle stay in the SwiftUI overlay above.
final class SkyStarRenderer: NSObject, MTKViewDelegate {
    /// Where the camera looks and how wide, read every frame.
    var projection: () -> SkyProjection? = { nil }
    /// Your sky right now, or nil before your location is known.
    var sky: () -> LocalSky? = { nil }

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var stars: MTLBuffer?, starCount = 0
    private var uploadedCount = -1
    /// The J2000-to-horizon rotation changes 0.004° a second, so it's worked out once a second.
    private var rotation: (matrix: simd_double3x3, at: Date)?

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
        view.preferredFramesPerSecond = 60
        view.delegate = self
        queue = device?.makeCommandQueue()
        if let device, let library = GraphShaders.library(device: device) {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "skyStarVertex")
            d.fragmentFunction = library.makeFunction(name: "skyStarFragment")
            let c = d.colorAttachments[0]!
            c.pixelFormat = view.colorPixelFormat
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try? device.makeRenderPipelineState(descriptor: d)
        }
        return view
    }

    /// Uploads the stars when the list changes. Brighter stars draw bigger; colors come from the
    /// shared star color scale, as on the night side of every map.
    func update(stars objects: [SkyObject]) {
        guard objects.count != uploadedCount, let device else { return }
        uploadedCount = objects.count
        let data: [SkyStarData] = objects.compactMap { object in
            guard case .star = object.kind else { return nil }
            let c = StarColor.color(bin: StarColor.bin(temperature: object.temperatureK ?? 5772))
            let radius = Float(min(max(3.4 - 0.5 * object.magnitude, 0.7), 5))
            let e = object.equatorial
            return SkyStarData(color: SIMD4(Float(c.r), Float(c.g), Float(c.b), 1),
                               direction: SIMD3(Float(e.x), Float(e.y), Float(e.z)), radius: radius)
        }
        starCount = data.count
        stars = data.isEmpty ? nil : data.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        if let pipeline, let stars, starCount > 0, let proj = projection(), let sky = currentRotation() {
            // Local sky (x north, y west, z up) to the camera: rows are screen right, screen up and
            // the way the camera looks.
            let view3 = simd_double3x3(rows: [proj.right, proj.up, proj.look])
            let m = view3 * sky
            func f(_ v: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), 0) }
            var uniforms = SkyUniformsData(
                j2000ToView: simd_float4x4(columns: (f(m.columns.0), f(m.columns.1), f(m.columns.2), SIMD4(0, 0, 0, 1))),
                viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                screen: SIMD2(Float(proj.size.width), Float(proj.size.height)),
                pixelsPerPoint: Float(view.contentScaleFactor),
                focal: Float(proj.focal)
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(stars, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SkyUniformsData>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: starCount)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private func currentRotation() -> simd_double3x3? {
        if let rotation, Date().timeIntervalSince(rotation.at) < 1 { return rotation.matrix }
        guard let sky = sky() else { return nil }
        let matrix = sky.fromJ2000
        rotation = (matrix, Date())
        return matrix
    }
}

/// Hosts the star renderer in SwiftUI.
struct SkyStarView: UIViewRepresentable {
    let renderer: SkyStarRenderer
    let objects: [SkyObject]
    let projection: () -> SkyProjection?
    let sky: () -> LocalSky?

    func makeUIView(context: Context) -> MTKView {
        let view = renderer.makeView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        renderer.projection = projection
        renderer.sky = sky
        renderer.update(stars: objects)
    }
}

// Must match SkyUniforms and SkyStar in GraphShaders.swift.
private struct SkyUniformsData {
    var j2000ToView: simd_float4x4
    var viewport: SIMD2<Float>
    var screen: SIMD2<Float>
    var pixelsPerPoint: Float
    var focal: Float
}

private struct SkyStarData {
    var color: SIMD4<Float>
    var direction: SIMD3<Float>
    var radius: Float
}
