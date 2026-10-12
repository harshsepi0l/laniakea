import CoreGraphics
import Foundation
import simd

/// Projects local sky directions onto the screen like the camera does: a pinhole camera looking
/// along `look`, with the camera's real field of view so drawn stars sit on the real ones.
struct SkyProjection {
    let look: SIMD3<Double>
    let up: SIMD3<Double>
    let right: SIMD3<Double>
    let size: CGSize
    /// Focal length in points.
    private(set) var focal: Double

    init(pointing: SkyPointing, size: CGSize, optics: CameraOptics?) {
        look = pointing.look
        up = pointing.up
        right = pointing.right
        self.size = size
        let long = Double(max(size.width, size.height)), short = Double(min(size.width, size.height))
        if let optics {
            // The picture fills the screen, so its long side is the larger of the screen's long side
            // and what the screen's short side needs at the sensor's aspect.
            let shownLong = max(long, short * optics.aspect)
            focal = shownLong / 2 / tan(optics.fieldOfViewDeg / 2 * .pi / 180)
        } else {
            // No camera: a 60° view across the long side.
            focal = long / 2 / tan(30 * Double.pi / 180)
        }
        focal *= pointing.zoom
    }

    /// Degrees across the screen's width.
    var widthDegrees: Double { 2 * atan(Double(size.width) / 2 / focal) * 180 / .pi }

    func point(_ direction: SIMD3<Double>) -> CGPoint? {
        let z = simd_dot(direction, look)
        guard z > 0.05 else { return nil }
        let x = simd_dot(direction, right) / z * focal
        let y = simd_dot(direction, up) / z * focal
        return CGPoint(x: Double(size.width) / 2 + x, y: Double(size.height) / 2 - y)
    }
}

/// Local directions of every sky object, recomputed once a second (the sky turns 0.004° a
/// second, far less than a pixel) instead of every frame.
final class SkyDirectionCache {
    private(set) var directions: [SIMD3<Double>] = []
    private var computedAt = Date.distantPast
    private var count = 0

    func directions(for objects: [SkyObject], sky: LocalSky) -> [SIMD3<Double>] {
        if objects.count != count || Date().timeIntervalSince(computedAt) > 1 {
            let rotation = sky.fromJ2000
            directions = objects.map { rotation * $0.equatorial }
            computedAt = Date()
            count = objects.count
        }
        return directions
    }
}
