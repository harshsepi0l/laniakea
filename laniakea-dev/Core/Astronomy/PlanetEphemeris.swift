import Foundation

/// Heliocentric planet positions from JPL's "Approximate Positions of the Planets"
/// (E.M. Standish, Table 1: valid 1800–2050, J2000 ecliptic). https://ssd.jpl.nasa.gov/planets/approx_pos.html
enum PlanetEphemeris {
    struct Elements {
        // Values at J2000 followed by rates per Julian century.
        let a: Double, aRate: Double             // semi-major axis, au
        let e: Double, eRate: Double             // eccentricity
        let i: Double, iRate: Double             // inclination, degrees
        let l: Double, lRate: Double             // mean longitude, degrees
        let peri: Double, periRate: Double       // longitude of perihelion, degrees
        let node: Double, nodeRate: Double       // longitude of ascending node, degrees
    }

    static let table1: [String: Elements] = [
        "mercury": .init(a: 0.38709927, aRate: 0.00000037, e: 0.20563593, eRate: 0.00001906, i: 7.00497902, iRate: -0.00594749,
                         l: 252.25032350, lRate: 149472.67411175, peri: 77.45779628, periRate: 0.16047689, node: 48.33076593, nodeRate: -0.12534081),
        "venus": .init(a: 0.72333566, aRate: 0.00000390, e: 0.00677672, eRate: -0.00004107, i: 3.39467605, iRate: -0.00078890,
                       l: 181.97909950, lRate: 58517.81538729, peri: 131.60246718, periRate: 0.00268329, node: 76.67984255, nodeRate: -0.27769418),
        // JPL lists the Earth–Moon barycenter; close enough to Earth at this scale.
        "earth": .init(a: 1.00000261, aRate: 0.00000562, e: 0.01671123, eRate: -0.00004392, i: -0.00001531, iRate: -0.01294668,
                       l: 100.46457166, lRate: 35999.37244981, peri: 102.93768193, periRate: 0.32327364, node: 0.0, nodeRate: 0.0),
        "mars": .init(a: 1.52371034, aRate: 0.00001847, e: 0.09339410, eRate: 0.00007882, i: 1.84969142, iRate: -0.00813131,
                      l: -4.55343205, lRate: 19140.30268499, peri: -23.94362959, periRate: 0.44441088, node: 49.55953891, nodeRate: -0.29257343),
        "jupiter": .init(a: 5.20288700, aRate: -0.00011607, e: 0.04838624, eRate: -0.00013253, i: 1.30439695, iRate: -0.00183714,
                         l: 34.39644051, lRate: 3034.74612775, peri: 14.72847983, periRate: 0.21252668, node: 100.47390909, nodeRate: 0.20469106),
        "saturn": .init(a: 9.53667594, aRate: -0.00125060, e: 0.05386179, eRate: -0.00050991, i: 2.48599187, iRate: 0.00193609,
                        l: 49.95424423, lRate: 1222.49362201, peri: 92.59887831, periRate: -0.41897216, node: 113.66242448, nodeRate: -0.28867794),
        "uranus": .init(a: 19.18916464, aRate: -0.00196176, e: 0.04725744, eRate: -0.00004397, i: 0.77263783, iRate: -0.00242939,
                        l: 313.23810451, lRate: 428.48202785, peri: 170.95427630, periRate: 0.40805281, node: 74.01692503, nodeRate: 0.04240589),
        "neptune": .init(a: 30.06992276, aRate: 0.00026291, e: 0.00859048, eRate: 0.00005105, i: 1.77004347, iRate: 0.00035372,
                         l: -55.12002969, lRate: 218.45945325, peri: 44.96476227, periRate: -0.32241464, node: 131.78422574, nodeRate: -0.00508664),
    ]

    static func julianCenturiesSinceJ2000(_ date: Date) -> Double {
        let julianDate = date.timeIntervalSince1970 / 86400 + 2440587.5
        return (julianDate - 2451545.0) / 36525
    }

    /// Position in au, J2000 ecliptic coordinates (x toward the vernal equinox, z toward ecliptic north).
    static func position(of planetID: String, at date: Date) -> SIMD3<Double>? {
        guard let el = table1[planetID] else { return nil }
        let t = julianCenturiesSinceJ2000(date)
        let o = Orbit(el, t)
        let meanAnomaly = normalizedDegrees(o.l - o.peri)
        return o.point(eccentricAnomalyDeg: solveKepler(meanAnomalyDeg: meanAnomaly, e: o.e))
    }

    /// Points around the planet's current orbit ellipse, in au.
    static func orbitPath(of planetID: String, at date: Date, samples: Int = 180) -> [SIMD3<Double>] {
        guard let el = table1[planetID] else { return [] }
        let o = Orbit(el, julianCenturiesSinceJ2000(date))
        return (0..<samples).map { o.point(eccentricAnomalyDeg: Double($0) * 360 / Double(samples)) }
    }

    private struct Orbit {
        let a, e, i, l, peri, node: Double

        init(_ el: Elements, _ t: Double) {
            a = el.a + el.aRate * t
            e = el.e + el.eRate * t
            i = el.i + el.iRate * t
            l = el.l + el.lRate * t
            peri = el.peri + el.periRate * t
            node = el.node + el.nodeRate * t
        }

        func point(eccentricAnomalyDeg eDeg: Double) -> SIMD3<Double> {
            let ea = eDeg * .pi / 180
            let xOrb = a * (cos(ea) - e)
            let yOrb = a * sqrt(1 - e * e) * sin(ea)
            let w = (peri - node) * .pi / 180
            let n = node * .pi / 180
            let inc = i * .pi / 180
            let x = (cos(w) * cos(n) - sin(w) * sin(n) * cos(inc)) * xOrb + (-sin(w) * cos(n) - cos(w) * sin(n) * cos(inc)) * yOrb
            let y = (cos(w) * sin(n) + sin(w) * cos(n) * cos(inc)) * xOrb + (-sin(w) * sin(n) + cos(w) * cos(n) * cos(inc)) * yOrb
            let z = sin(w) * sin(inc) * xOrb + cos(w) * sin(inc) * yOrb
            return SIMD3(x, y, z)
        }
    }

    private static func solveKepler(meanAnomalyDeg m: Double, e: Double) -> Double {
        let eStar = e * 180 / .pi
        var ea = m + eStar * sin(m * .pi / 180)
        for _ in 0..<10 {
            let deltaM = m - (ea - eStar * sin(ea * .pi / 180))
            let deltaE = deltaM / (1 - e * cos(ea * .pi / 180))
            ea += deltaE
            if abs(deltaE) < 1e-7 { break }
        }
        return ea
    }

    private static func normalizedDegrees(_ angle: Double) -> Double {
        var x = angle.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }
}
