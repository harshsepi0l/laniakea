import simd

/// Flat, top-down layout of the solar system. Orbits are evenly spaced so every planet is visible;
/// each planet keeps its true direction from the Sun.
enum SceneSpace {
    // Each planet's mean distance (au) mapped to an evenly spaced radius; values in between are
    // interpolated so eccentric orbits keep their shape.
    private static let anchors: [(au: Double, scene: Double)] = [
        (0, 0), (0.387, 1.4), (0.723, 2.0), (1.0, 2.6), (1.524, 3.2),
        (5.203, 4.2), (9.537, 5.0), (19.19, 5.8), (30.07, 6.6),
    ]

    static let outerRadius = 6.6

    static func distance(au: Double) -> Double {
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where au <= upper.au {
            let f = (au - lower.au) / (upper.au - lower.au)
            return lower.scene + (upper.scene - lower.scene) * f
        }
        let last = anchors[anchors.count - 1], previous = anchors[anchors.count - 2]
        return last.scene + (au - last.au) * (last.scene - previous.scene) / (last.au - previous.au)
    }

    /// J2000 ecliptic coordinates in au, seen from above the ecliptic, as flat layout coordinates.
    static func position(_ v: SIMD3<Double>) -> SIMD2<Double> {
        let flat = SIMD2(v.x, v.y)
        let r = simd_length(flat)
        guard r > 0 else { return .zero }
        return flat / r * distance(au: simd_length(v))
    }
}
