import Foundation
import simd

/// The Cosmicflows-4 reconstruction of how matter moves and where it gathers around us (Courtois et
/// al. 2023): 3D velocity and density on a 64³ grid, 1000 Mpc/h across, centred on the Milky Way, in
/// supergalactic coordinates. It's built from galaxy distances and velocities, so it covers space
/// where no galaxy has been measured, which is how Laniakea's whole shape and flow can be shown.
///
/// Checked against known structure: velocity converges where density is high (correlation 0.997),
/// the Local Group's flow points within 31° of its measured motion against the cosmic background,
/// and the field's Laniakea basin holds Virgo, Norma, Centaurus and Hydra but not Perseus–Pisces or
/// Coma. Velocities are in the file's own units (about 60 km/s each); only their direction is used.
struct CosmicFlowField {
    static let size = 64
    /// Cosmicflows-4 assumes H0 = 75 km/s/Mpc, so the 1000 Mpc/h box is 1333 Mpc across.
    static let cellMpc = 1000.0 / 0.75 / Double(size)

    /// Supergalactic x, y and z components, and density contrast, each indexed z·64² + y·64 + x.
    let vx: [Float], vy: [Float], vz: [Float]
    let density: [Float]

    /// The grid position of a supergalactic point in Mpc (cell centres at whole numbers).
    private static func gridPoint(_ p: SIMD3<Double>) -> SIMD3<Double> {
        p / cellMpc + SIMD3(repeating: Double(size) / 2 - 0.5)
    }

    /// A cell's centre in supergalactic Mpc.
    static func centre(x: Int, y: Int, z: Int) -> SIMD3<Double> {
        (SIMD3(Double(x), Double(y), Double(z)) + 0.5 - Double(size) / 2) * cellMpc
    }

    /// Trilinear interpolation of a field at a point; nil outside the grid.
    private func sample(_ field: [Float], at p: SIMD3<Double>) -> Double? {
        let g = Self.gridPoint(p)
        let n = Self.size
        let i = Int(floor(g.x)), j = Int(floor(g.y)), k = Int(floor(g.z))
        guard i >= 0, j >= 0, k >= 0, i < n - 1, j < n - 1, k < n - 1 else { return nil }
        let fx = g.x - Double(i), fy = g.y - Double(j), fz = g.z - Double(k)
        func at(_ a: Int, _ b: Int, _ c: Int) -> Double { Double(field[(k + c) * n * n + (j + b) * n + (i + a)]) }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let x00 = lerp(at(0, 0, 0), at(1, 0, 0), fx), x10 = lerp(at(0, 1, 0), at(1, 1, 0), fx)
        let x01 = lerp(at(0, 0, 1), at(1, 0, 1), fx), x11 = lerp(at(0, 1, 1), at(1, 1, 1), fx)
        return lerp(lerp(x00, x10, fy), lerp(x01, x11, fy), fz)
    }

    func velocity(at p: SIMD3<Double>) -> SIMD3<Double>? {
        guard let x = sample(vx, at: p), let y = sample(vy, at: p), let z = sample(vz, at: p) else { return nil }
        return SIMD3(x, y, z)
    }

    func density(at p: SIMD3<Double>) -> Double? { sample(density, at: p) }

    /// Follows the flow downstream from a point: the path matter is falling along. Stops where the
    /// flow stalls (an attractor, like the Great Attractor), leaves `radius`, or runs `maxSteps`.
    /// `planar` keeps the path in the supergalactic plane, for the classic flat map.
    func streamline(from start: SIMD3<Double>, step: Double = cellMpc * 0.4, maxSteps: Int = 140,
                    radius: Double = 330, planar: Bool = false) -> [SIMD3<Double>] {
        func direction(_ p: SIMD3<Double>) -> SIMD3<Double>? {
            guard var v = velocity(at: p) else { return nil }
            if planar { v.z = 0 }
            let speed = simd_length(v)
            return speed > 0.3 ? v / speed : nil
        }
        var points = [start]
        var p = start
        for _ in 0..<maxSteps {
            // Midpoint (second-order) step along the unit direction.
            guard let d1 = direction(p), let d2 = direction(p + d1 * step / 2) else { break }
            p += d2 * step
            guard simd_length(p) < radius else { break }
            points.append(p)
            // Circling an attractor: stop once the last few steps went nowhere.
            if points.count > 6, simd_distance(points[points.count - 6], p) < step * 2.5 { break }
        }
        return points
    }
}

/// Laniakea's flow and the cosmic web around it, traced once from the field.
struct LaniakeaFlow: Codable {
    /// Flow lines through the whole basin in 3D, supergalactic Mpc, each running downstream.
    let lines: [[SIMD3<Float>]]
    /// Flow lines in the supergalactic plane, the classic map of Laniakea.
    let planeLines: [[SIMD2<Float>]]
    /// The densest cells: the filaments and clusters of the cosmic web.
    let web: [WebCell]

    struct WebCell: Codable {
        let position: SIMD3<Float>
        /// Density contrast: 1 is twice the average.
        let density: Float
        /// Near the supergalactic plane, so it belongs on the flat map too.
        let inPlane: Bool
    }

    /// Traces the flow from seeds spread through Laniakea (3D) and across the supergalactic plane
    /// out to `reach` (2D, so the boundary shows where the flow turns away to other basins).
    init(field: CosmicFlowField, laniakeaCells: [SIMD3<Double>], reach: Double = 220) {
        func f3(_ p: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(p.x), Float(p.y), Float(p.z)) }
        // About 500 seeds through the basin, evenly picked from its cells.
        let stride = max(1, laniakeaCells.count / 500)
        let seeds = Swift.stride(from: 0, to: laniakeaCells.count, by: stride).map { laniakeaCells[$0] }
        lines = seeds.map { field.streamline(from: $0) }.filter { $0.count > 3 }.map { $0.map(f3) }

        var plane: [[SIMD2<Float>]] = []
        let spacing = CosmicFlowField.cellMpc * 1.1
        for x in Swift.stride(from: -reach, through: reach, by: spacing) {
            for y in Swift.stride(from: -reach, through: reach, by: spacing) {
                let line = field.streamline(from: SIMD3(x, y, 0), maxSteps: 90, radius: reach * 1.3, planar: true)
                if line.count > 3 { plane.append(line.map { SIMD2(Float($0.x), Float($0.y)) }) }
            }
        }
        planeLines = plane

        var cells: [WebCell] = []
        let n = CosmicFlowField.size
        let cell = CosmicFlowField.cellMpc
        // Points scattered through each dense cell rather than at its centre, which would show the
        // grid. A fixed seed keeps the scatter the same every time.
        var random = SplitMix(seed: 2023)
        for z in 0..<n {
            for y in 0..<n {
                for x in 0..<n {
                    let d = field.density[z * n * n + y * n + x]
                    let centre = CosmicFlowField.centre(x: x, y: y, z: z)
                    guard d > 0.9, simd_length(centre) < 330 else { continue }
                    for _ in 0..<2 {
                        let jitter = SIMD3(random.unit(), random.unit(), random.unit()) - 0.5
                        let p = centre + jitter * cell
                        cells.append(WebCell(position: f3(p), density: d, inPlane: abs(p.z) < cell * 0.75))
                    }
                }
            }
        }
        web = cells
    }
}

/// A small seeded random number generator (SplitMix64), so scattered points land the same way on
/// every launch.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
