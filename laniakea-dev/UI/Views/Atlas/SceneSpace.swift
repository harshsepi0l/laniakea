import simd

/// Flat, top-down layout of the solar system. Orbits are evenly spaced so every planet is visible;
/// each planet keeps its true direction from the Sun.
struct SceneSpace {
    /// Each planet's semi-major axis (au) mapped to a ring radius; distances in between are
    /// interpolated so eccentric orbits keep their shape.
    private let anchors: [(au: Double, scene: Double)]

    let outerRadius: Double

    private static let firstRing = 1.4
    private static let innerStep = 0.6
    private static let outerStep = 0.8
    /// Extra room for the asteroid belt between the rocky planets and the giants.
    private static let beltStep = 1.0
    private static let beltAU = 2.5

    init(semiMajorAxesAU: [Double]) {
        var anchors: [(au: Double, scene: Double)] = [(0, 0)]
        for au in semiMajorAxesAU.sorted() {
            guard let last = anchors.last else { continue }
            let step: Double
            if last.au == 0 { step = Self.firstRing }
            else if last.au < Self.beltAU && au > Self.beltAU { step = Self.beltStep }
            else { step = au < Self.beltAU ? Self.innerStep : Self.outerStep }
            anchors.append((au, last.scene + step))
        }
        if anchors.count < 2 { anchors.append((1, Self.firstRing)) }
        self.anchors = anchors
        outerRadius = anchors[anchors.count - 1].scene
    }

    func distance(au: Double) -> Double {
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where au <= upper.au {
            let f = (au - lower.au) / (upper.au - lower.au)
            return lower.scene + (upper.scene - lower.scene) * f
        }
        let last = anchors[anchors.count - 1], previous = anchors[anchors.count - 2]
        return last.scene + (au - last.au) * (last.scene - previous.scene) / (last.au - previous.au)
    }

    /// J2000 ecliptic coordinates in au, seen from above the ecliptic, as flat layout coordinates.
    func position(_ v: SIMD3<Double>) -> SIMD2<Double> {
        let flat = SIMD2(v.x, v.y)
        let r = simd_length(flat)
        guard r > 0 else { return .zero }
        return flat / r * distance(au: simd_length(v))
    }
}
