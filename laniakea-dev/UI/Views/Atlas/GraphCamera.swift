import Combine
import MetalKit
import simd
import SwiftUI

/// Where the map's camera is. Flat, it looks straight down on the layout plane, as Atlas always
/// has; in 3D it tilts toward the horizon and can turn around the point in the middle of the screen.
struct GraphCameraState: Equatable {
    /// The layout point in the middle of the screen, relative to the scene's fit centre.
    var target: SIMD3<Double> = .zero
    var zoom: Double = 1
    /// Turn around the vertical, radians.
    var yaw: Double = 0
    /// Tilt from straight down, radians; 0 is the flat map.
    var tilt: Double = 0

    /// The tilt the 3D button goes to, and the most a drag can tilt.
    static let tilt3D = 1.0
    static let maxTilt = 1.38
    static let maxZoom = 4000.0

    var is3D: Bool { tilt > 0.01 }
}

/// Layout coordinates to the screen for one camera state: the same maths on the CPU (names, taps)
/// and the GPU (`worldToClip`), so the two always agree.
struct GraphProjection {
    let size: CGSize
    /// Points per layout unit at the target's depth.
    let scale: Double
    let rotation: simd_double3x3
    let target: SIMD3<Double>
    let fitCenter: SIMD3<Double>
    /// Distance from the camera to the target in layout units, or nil looking straight down (no
    /// perspective). Perspective fades in with the tilt so the flat map is exactly as before.
    let distance: Double?

    init(scene: GraphScene, state: GraphCameraState, size: CGSize) {
        self.size = size
        let base = Double(min(size.width, size.height)) / 2 * 0.92 / scene.fitRadius
        scale = base * state.zoom
        // Turn about the vertical by the yaw, then tilt the top of the map away from you.
        let cy = cos(state.yaw), sy = sin(state.yaw), ct = cos(state.tilt), st = sin(state.tilt)
        let yawMatrix = simd_double3x3(rows: [SIMD3(cy, -sy, 0), SIMD3(sy, cy, 0), SIMD3(0, 0, 1)])
        let tiltMatrix = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, ct, st), SIMD3(0, -st, ct)])
        rotation = tiltMatrix * yawMatrix
        target = state.target
        fitCenter = SIMD3(scene.fitCenter.x, scene.fitCenter.y, 0)
        let strength = min(sin(state.tilt) / sin(GraphCameraState.tilt3D), 1.2)
        // Far enough back that the near side doesn't balloon over the far side.
        distance = strength > 0.001 ? scene.fitRadius * 4 / state.zoom / strength : nil
    }

    /// A layout position (absolute, as the scene stores it) in camera space: x right, y up, z toward you.
    func view(_ p: SIMD3<Double>) -> SIMD3<Double> {
        rotation * (p - fitCenter - target)
    }

    /// Where a layout position lands on screen and how much nearer it is than the target (1 at
    /// the target's depth); nil behind the camera.
    func point(_ p: SIMD3<Double>) -> (point: CGPoint, nearness: Double)? {
        let v = view(p)
        var f = 1.0
        if let distance {
            guard v.z < distance * 0.97 else { return nil }
            f = distance / (distance - v.z)
        }
        return (CGPoint(x: Double(size.width) / 2 + v.x * scale * f, y: Double(size.height) / 2 - v.y * scale * f), f)
    }

    /// A screen movement in points as a layout movement in the plane facing the camera at the
    /// target's depth (for panning and zooming about a point).
    func layoutDelta(screen d: CGSize) -> SIMD3<Double> {
        rotation.transpose * SIMD3(Double(d.width) / scale, -Double(d.height) / scale, 0)
    }

    /// Layout positions relative to the fit centre to clip space.
    var worldToClip: simd_float4x4 {
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        let d = distance ?? 1
        let sx = 2 * scale / w * d, sy = 2 * scale / h * d
        let r = rotation
        // clip = P · (R · (p − target)), with P scaling x and y and putting depth into w.
        func row(_ i: Int) -> SIMD3<Double> { SIMD3(r[0][i], r[1][i], r[2][i]) }
        let rx = row(0), ry = row(1), rz = row(2)
        let t = target
        let xRow = SIMD4(rx * sx, -simd_dot(rx, t) * sx)
        let yRow = SIMD4(ry * sy, -simd_dot(ry, t) * sy)
        let wRow: SIMD4<Double> = distance == nil ? SIMD4(0, 0, 0, 1) : SIMD4(-rz, simd_dot(rz, t) + d)
        let zRow = wRow * 0.5
        func f(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
        return simd_float4x4(rows: [f(xRow), f(yRow), f(zRow), f(wRow)])
    }
}

/// The live camera. Gestures change it directly and ask for a redraw, without going through
/// SwiftUI state, so moving the map never rebuilds any views.
final class GraphCamera {
    var state = GraphCameraState()
    /// Fingers' gestures under way (pan, pinch and twist can run together).
    var activeGestures = 0 {
        didSet { if activeGestures == 0 { twoFinger = TwoFinger() } }
    }

    /// What a two-finger touch is doing, decided by how the fingers move so a pinch doesn't also
    /// tilt and turn the map. Reset when all fingers lift.
    struct TwoFinger {
        var pinch: CGFloat = 1      // how far the fingers have spread since touching down
        var twist: CGFloat = 0      // how far they've turned
        var slide: CGFloat = 0      // how far they've moved up or down together
        var zooms = false, turns = false, tilts = false
    }
    var twoFinger = TwoFinger()
    /// The layout point (relative to the fit centre) a pinch zooms toward, chosen when it starts.
    var pinchPivot: SIMD3<Double>?

    private struct Animation {
        let from: GraphCameraState, to: GraphCameraState
        let start: CFTimeInterval, duration: CFTimeInterval
        let completion: () -> Void
    }
    private var animation: Animation?
    weak var view: MTKView?
    /// Keeps drawing every frame while time runs.
    var isTimeRunning = false { didSet { updateRunning() } }

    var isAnimating: Bool { animation != nil }

    func changed() {
        view?.setNeedsDisplay()
    }

    /// Glides to another camera with an ease in and out, then calls `completion`.
    func animate(to target: GraphCameraState, duration: CFTimeInterval = 0.45, completion: @escaping () -> Void) {
        animation = Animation(from: state, to: target, start: CACurrentMediaTime(), duration: duration, completion: completion)
        updateRunning()
    }

    /// Moves the animation on to now; returns its completion once it's done.
    func step(now: CFTimeInterval) -> (() -> Void)? {
        guard let a = animation else { return nil }
        let t = min(max((now - a.start) / a.duration, 0), 1)
        let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * e }
        // Zoom eases in log space so big jumps feel even; yaw takes the short way round.
        var dyaw = (a.to.yaw - a.from.yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if dyaw > .pi { dyaw -= 2 * .pi } else if dyaw < -.pi { dyaw += 2 * .pi }
        state = GraphCameraState(
            target: a.from.target + (a.to.target - a.from.target) * e,
            zoom: exp(mix(log(a.from.zoom), log(a.to.zoom))),
            yaw: a.from.yaw + dyaw * e,
            tilt: mix(a.from.tilt, a.to.tilt)
        )
        guard t >= 1 else { return nil }
        state = a.to
        animation = nil
        updateRunning()
        return a.completion
    }

    private func updateRunning() {
        let continuous = animation != nil || isTimeRunning
        view?.enableSetNeedsDisplay = !continuous
        view?.isPaused = !continuous
        if !continuous { view?.setNeedsDisplay() }
    }
}

/// Time for places measured in years: a star field drifting over millennia, galaxy groups over
/// millions of years. Starts at now and runs only while playing; it stops only where the model
/// stops meaning anything (before the universe began).
final class DeepTimeClock: ObservableObject {
    @Published var isPlaying = false { didSet { lastTick = nil } }
    @Published var speedIndex = 1
    @Published var runsBackward = false
    /// Years from now; negative is the past.
    private(set) var years: Double = 0
    private var lastTick: CFTimeInterval?

    func tick(now: CFTimeInterval, motion: GraphScene.Motion) {
        defer { lastTick = now }
        guard isPlaying, let last = lastTick else { return }
        let elapsed = now - last
        // Skip big gaps (backgrounding) instead of jumping ahead.
        guard elapsed > 0, elapsed < 0.25, motion.speeds.indices.contains(speedIndex) else { return }
        let rate = motion.speeds[speedIndex].yearsPerSecond * (runsBackward ? -1 : 1)
        let next = years + rate * elapsed
        let crossed = motion.isPrediction(next) != motion.isPrediction(years)
        if next <= -motion.maxPastYears || next >= motion.maxFutureYears {
            years = next < 0 ? -motion.maxPastYears : motion.maxFutureYears
            DispatchQueue.main.async { self.isPlaying = false }
        } else {
            years = next
            // So the caption and the time control switch to saying it's a prediction.
            if crossed { DispatchQueue.main.async { self.objectWillChange.send() } }
        }
    }

    func reset() {
        isPlaying = false
        years = 0
        objectWillChange.send()
    }

    /// Back to now at a place's own starting speed, going forward.
    func reset(for motion: GraphScene.Motion?) {
        speedIndex = motion?.defaultSpeedIndex ?? 1
        runsBackward = false
        reset()
    }

    /// "Now", "+12,400 years", "−1.2 million years".
    static func label(years: Double) -> String {
        guard abs(years) >= 0.5 else { return "Now" }
        let sign = years > 0 ? "+" : "−"
        let a = abs(years)
        let text: String
        switch a {
        case 1e9...: text = "\((a / 1e9).formatted(.number.precision(.fractionLength(2)))) billion years"
        case 1e6...: text = "\((a / 1e6).formatted(.number.precision(.fractionLength(a < 1e8 ? 1 : 0)))) million years"
        default: text = "\(a.formatted(.number.precision(.fractionLength(0)))) years"
        }
        return sign + text
    }
}
