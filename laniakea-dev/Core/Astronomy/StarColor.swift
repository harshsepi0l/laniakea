import Foundation

/// Star colors from the B−V color index. Temperature uses Ballesteros (2012, EPL 97, 34008);
/// colors follow the O–M spectral classes, shifted slightly warm so G stars like the Sun read as orange.
enum StarColor {
    struct RGB: Equatable {
        let r: Double, g: Double, b: Double
    }

    static func temperature(bv: Double) -> Double {
        4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62))
    }

    // Anchor colors at representative temperatures, blended in log-temperature between them.
    private static let anchors: [(t: Double, color: RGB)] = [
        (3_000, RGB(r: 1.00, g: 0.33, b: 0.30)),   // M: red
        (4_250, RGB(r: 1.00, g: 0.50, b: 0.25)),   // K: red-orange
        (5_500, RGB(r: 1.00, g: 0.62, b: 0.18)),   // G: orange (the Sun)
        (6_750, RGB(r: 1.00, g: 0.90, b: 0.72)),   // F: yellow-white
        (8_750, RGB(r: 0.97, g: 0.97, b: 1.00)),   // A: white
        (15_000, RGB(r: 0.72, g: 0.82, b: 1.00)),  // B: blue-white
        (35_000, RGB(r: 0.58, g: 0.66, b: 1.00)),  // O: blue-violet
    ]

    static func color(temperature t: Double) -> RGB {
        if t <= anchors[0].t { return anchors[0].color }
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where t <= upper.t {
            let f = (log(t) - log(lower.t)) / (log(upper.t) - log(lower.t))
            return RGB(
                r: lower.color.r + (upper.color.r - lower.color.r) * f,
                g: lower.color.g + (upper.color.g - lower.color.g) * f,
                b: lower.color.b + (upper.color.b - lower.color.b) * f
            )
        }
        return anchors[anchors.count - 1].color
    }

    /// Bins of temperature for drawing many stars in a few batches, from cool to hot.
    static let binEdges: [Double] = [3_300, 3_900, 4_600, 5_300, 5_950, 6_600, 7_300, 9_000, 12_000, 20_000]

    static func bin(temperature t: Double) -> Int {
        binEdges.firstIndex { t < $0 } ?? binEdges.count
    }

    /// A bin's color, taken at the middle of its range in log temperature.
    static func color(bin: Int) -> RGB {
        let low = bin == 0 ? 2_800 : binEdges[bin - 1]
        let high = bin == binEdges.count ? 30_000 : binEdges[bin]
        return color(temperature: (low * high).squareRoot())
    }

    static func color(bv: Double) -> RGB {
        color(temperature: temperature(bv: bv))
    }
}
