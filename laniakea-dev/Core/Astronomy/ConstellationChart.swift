import Foundation
import simd

/// A constellation measured from the IAU boundaries: where it is, how big it is, its stars, and a
/// chart of it in the same projection the sky-survey photo uses, so the two line up.
struct ConstellationProfile {
    let abbreviation: String
    let centreRA: Double
    let centreDec: Double
    /// Width of the frame on the sky in degrees (in the ARC projection, as hips2fits measures it).
    let fovDegrees: Double
    /// Area in square degrees, from the boundaries sampled every degree.
    let areaSquareDegrees: Double
    let stars: [NakedEyeStar]
    let chart: FactHeader.SkyChart

    static let aspect = 640.0 / 900.0

    /// Builds the profile, or nil if the abbreviation isn't one of the 88. Samples the whole sky once
    /// (about 65,000 lookups), so run it off the main thread.
    init?(abbreviation: String, boundaries: ConstellationBoundaries, nakedEye: [NakedEyeStar]) {
        // 1. Sample the sphere at 1° to find the constellation's area and centre.
        var area = 0.0, sum = SIMD3<Double>.zero
        var samples: [SIMD3<Double>] = []
        for dec in stride(from: -89.5, to: 90, by: 1.0) {
            let weight = cos(dec * .pi / 180)
            for ra in stride(from: 0.5, to: 360, by: 1.0) {
                let v = SkyCoordinates.cartesian(longitudeDeg: ra, latitudeDeg: dec, distance: 1)
                guard boundaries.constellation(of: v) == abbreviation else { continue }
                area += weight
                sum += v
                samples.append(v)
            }
        }
        guard !samples.isEmpty else { return nil }
        let centre = simd_normalize(sum)
        let c = SkyCoordinates.spherical(centre)
        // Tangent-plane axes at the centre: north toward the pole, east toward rising RA.
        let pole = SIMD3<Double>(0, 0, 1)
        let north = simd_normalize(pole - simd_dot(pole, centre) * centre)
        let east = simd_cross(north, centre)
        // Zenithal equidistant (ARC) projection: distance from the centre is the true angle, so even
        // Hydra (over 100° long) fits without the stretching a flat projection gives. On screen east
        // is left, as on any sky chart.
        func project(_ v: SIMD3<Double>) -> SIMD2<Double>? {
            let angle = acos(max(-1, min(1, simd_dot(v, centre))))
            guard angle < 2.6 else { return nil }
            let e = simd_dot(v, east), n = simd_dot(v, north), across = (e * e + n * n).squareRoot()
            guard across > 1e-12 else { return .zero }
            return SIMD2(-e / across * angle, n / across * angle)
        }
        func unproject(_ x: Double, _ y: Double) -> SIMD3<Double> {
            let angle = (x * x + y * y).squareRoot()
            guard angle > 1e-12 else { return centre }
            return simd_normalize(cos(angle) * centre + sin(angle) * (-x / angle * east + y / angle * north))
        }

        // 2. Frame it with a margin, at the photo's aspect.
        var maxX = 0.0, maxY = 0.0
        for v in samples {
            guard let p = project(v) else { continue }
            maxX = max(maxX, abs(p.x)); maxY = max(maxY, abs(p.y))
        }
        let width = max(2 * maxX, 2 * maxY / Self.aspect) * 1.15
        let height = width * Self.aspect

        // 3. The boundary, by marching squares on a fine grid over the frame.
        let columns = 96, rows = Int(Double(columns) * Self.aspect)
        var inside = [[Bool]](repeating: [Bool](repeating: false, count: columns + 1), count: rows + 1)
        for j in 0...rows {
            for i in 0...columns {
                let x = (Double(i) / Double(columns) - 0.5) * width, y = (Double(j) / Double(rows) - 0.5) * height
                let v = unproject(x, y)
                inside[j][i] = boundaries.constellation(of: v) == abbreviation
            }
        }
        var outline: [FactHeader.SkyChart.Segment] = []
        func point(_ i: Double, _ j: Double) -> (Double, Double) { (i / Double(columns) - 0.5, (j / Double(rows) - 0.5) * Self.aspect) }
        for j in 0..<rows {
            for i in 0..<columns {
                let (x, y) = (Double(i), Double(j))
                let bottom = point(x + 0.5, y), right = point(x + 1, y + 0.5), top = point(x + 0.5, y + 1), left = point(x, y + 0.5)
                let code = (inside[j][i] ? 1 : 0) | (inside[j][i + 1] ? 2 : 0) | (inside[j + 1][i + 1] ? 4 : 0) | (inside[j + 1][i] ? 8 : 0)
                var pairs: [((Double, Double), (Double, Double))] = []
                switch code {
                case 1, 14: pairs = [(left, bottom)]
                case 2, 13: pairs = [(bottom, right)]
                case 3, 12: pairs = [(left, right)]
                case 4, 11: pairs = [(right, top)]
                case 6, 9: pairs = [(bottom, top)]
                case 7, 8: pairs = [(left, top)]
                case 5: pairs = [(left, top), (bottom, right)]
                case 10: pairs = [(left, bottom), (right, top)]
                default: break
                }
                outline += pairs.map { .init(x1: $0.0.0, y1: $0.0.1, x2: $0.1.0, y2: $0.1.1) }
            }
        }

        // 4. Every naked-eye star in the frame; the constellation's own get names.
        var members: [NakedEyeStar] = []
        var chartStars: [FactHeader.SkyChart.Star] = []
        for star in nakedEye {
            let v = SkyCoordinates.cartesian(longitudeDeg: star.raDeg, latitudeDeg: star.decDeg, distance: 1)
            guard let p = project(v), abs(p.x) < width / 2, abs(p.y) < height / 2 else { continue }
            let isMember = boundaries.constellation(of: v) == abbreviation
            if isMember { members.append(star) }
            let label = isMember && star.magnitude < 3.6 ? (star.properName ?? star.designation.map { String($0.prefix { $0 != " " }) }) : nil
            chartStars.append(.init(x: p.x / width, y: p.y / width, magnitude: star.magnitude, temperatureK: star.temperatureK, label: label))
        }

        self.abbreviation = abbreviation
        centreRA = c.l
        centreDec = c.b
        // hips2fits measures an ARC image's width as the angle across it, in degrees.
        fovDegrees = width * 180 / .pi
        // Each sample is a 1° × 1° cell, shrinking by cos(dec) toward the poles.
        areaSquareDegrees = area
        stars = members.sorted { $0.magnitude < $1.magnitude }
        chart = FactHeader.SkyChart(stars: chartStars, outline: outline, aspect: Self.aspect)
    }
}
