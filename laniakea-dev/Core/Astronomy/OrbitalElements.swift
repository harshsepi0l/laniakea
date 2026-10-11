import Foundation
import simd

/// Heliocentric osculating orbital elements (J2000 ecliptic) at one moment, as JPL Horizons reports them.
/// Positions at other dates follow a two-body Kepler orbit, which stays accurate to well under a
/// degree for years either side of the epoch.
struct OrbitalElements: Codable, Equatable {
    let epochJulianDay: Double
    let eccentricity: Double
    let semiMajorAxisAU: Double
    let inclinationDeg: Double
    let ascendingNodeDeg: Double
    let argumentOfPerihelionDeg: Double
    let meanAnomalyDeg: Double
    let meanMotionDegPerDay: Double
    let periodDays: Double

    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400 + 2440587.5
    }

    /// Position in au, J2000 ecliptic coordinates (x toward the vernal equinox, z toward ecliptic north).
    func position(at date: Date) -> SIMD3<Double> {
        let days = Self.julianDay(date) - epochJulianDay
        let meanAnomaly = (meanAnomalyDeg + meanMotionDegPerDay * days)
            .truncatingRemainder(dividingBy: 360) * .pi / 180
        let ea = Self.solveKepler(meanAnomaly: meanAnomaly, e: eccentricity)

        let a = semiMajorAxisAU, e = eccentricity
        let xOrb = a * (cos(ea) - e)
        let yOrb = a * sqrt(1 - e * e) * sin(ea)
        let w = argumentOfPerihelionDeg * .pi / 180
        let n = ascendingNodeDeg * .pi / 180
        let i = inclinationDeg * .pi / 180
        let x = (cos(w) * cos(n) - sin(w) * sin(n) * cos(i)) * xOrb + (-sin(w) * cos(n) - cos(w) * sin(n) * cos(i)) * yOrb
        let y = (cos(w) * sin(n) + sin(w) * cos(n) * cos(i)) * xOrb + (-sin(w) * sin(n) + cos(w) * cos(n) * cos(i)) * yOrb
        let z = sin(w) * sin(i) * xOrb + cos(w) * sin(i) * yOrb
        return SIMD3(x, y, z)
    }

    /// Eccentric anomaly (radians) for a mean anomaly (radians), by Newton's method.
    private static func solveKepler(meanAnomaly m: Double, e: Double) -> Double {
        var ea = e < 0.8 ? m : .pi
        for _ in 0..<15 {
            let delta = (ea - e * sin(ea) - m) / (1 - e * cos(ea))
            ea -= delta
            if abs(delta) < 1e-12 { break }
        }
        return ea
    }
}
