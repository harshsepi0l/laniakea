import Foundation
import simd

enum SkyCoordinates {
    /// Cartesian point from spherical coordinates (longitude and latitude in degrees) and a distance.
    static func cartesian(longitudeDeg: Double, latitudeDeg: Double, distance: Double) -> SIMD3<Double> {
        let l = longitudeDeg * .pi / 180, b = latitudeDeg * .pi / 180
        return SIMD3(cos(b) * cos(l), cos(b) * sin(l), sin(b)) * distance
    }

    /// Distance in Mpc from a distance modulus.
    static func megaparsecs(distanceModulus dm: Double) -> Double {
        pow(10, dm / 5 + 1) / 1e6
    }

    /// Rows of the equatorial J2000 → Galactic rotation, from the Hipparcos catalogue introduction
    /// (ESA 1997, vol. 1, §1.5.3).
    private static let galacticRows = [
        SIMD3(-0.0548755604, -0.8734370902, -0.4838350155),
        SIMD3(0.4941094279, -0.4448296300, 0.7469822445),
        SIMD3(-0.8676661490, -0.1980763734, 0.4559837762),
    ]

    /// Equatorial J2000 (RA, Dec) to Galactic (l, b), both in degrees.
    static func galactic(raDeg: Double, decDeg: Double) -> (l: Double, b: Double) {
        let v = cartesian(longitudeDeg: raDeg, latitudeDeg: decDeg, distance: 1)
        return spherical(SIMD3(simd_dot(galacticRows[0], v), simd_dot(galacticRows[1], v), simd_dot(galacticRows[2], v)))
    }

    /// The supergalactic axes in Galactic coordinates: the pole at Galactic (l 47.37°, b 6.32°) and zero
    /// longitude at Galactic (137.37°, 0°) (de Vaucouleurs 1976).
    private static let supergalacticAxes: (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) = {
        let x = cartesian(longitudeDeg: 137.37, latitudeDeg: 0, distance: 1)
        let z = cartesian(longitudeDeg: 47.37, latitudeDeg: 6.32, distance: 1)
        return (x, simd_cross(z, x), z)
    }()

    /// Equatorial J2000 (RA, Dec) to a supergalactic unit vector.
    static func supergalacticDirection(raDeg: Double, decDeg: Double) -> SIMD3<Double> {
        let g = galactic(raDeg: raDeg, decDeg: decDeg)
        let v = cartesian(longitudeDeg: g.l, latitudeDeg: g.b, distance: 1)
        let a = supergalacticAxes
        return SIMD3(simd_dot(v, a.x), simd_dot(v, a.y), simd_dot(v, a.z))
    }

    /// Equatorial J2000 unit vector for a Galactic Cartesian position.
    static func equatorial(galactic g: SIMD3<Double>) -> SIMD3<Double> {
        simd_normalize(galacticRows[0] * g.x + galacticRows[1] * g.y + galacticRows[2] * g.z)
    }

    /// Equatorial J2000 unit vector for a supergalactic Cartesian position.
    static func equatorial(supergalactic s: SIMD3<Double>) -> SIMD3<Double> {
        let a = supergalacticAxes
        return equatorial(galactic: a.x * s.x + a.y * s.y + a.z * s.z)
    }

    /// Equatorial J2000 unit vector for a position in the J2000 ecliptic frame.
    static func equatorial(ecliptic e: SIMD3<Double>) -> SIMD3<Double> {
        let obliquity = 23.4392911 * Double.pi / 180
        return simd_normalize(SIMD3(e.x, e.y * cos(obliquity) - e.z * sin(obliquity), e.y * sin(obliquity) + e.z * cos(obliquity)))
    }

    /// Longitude (0…360°) and latitude in degrees of a direction.
    static func spherical(_ v: SIMD3<Double>) -> (l: Double, b: Double) {
        var l = atan2(v.y, v.x) * 180 / .pi
        if l < 0 { l += 360 }
        return (l, asin(max(-1, min(1, v.z / simd_length(v)))) * 180 / .pi)
    }

    /// Precesses an equatorial J2000 direction to the equator and equinox of 1875, the frame the IAU
    /// constellation boundaries were drawn in. IAU 1976 precession angles (Lieske et al. 1977).
    static func precessToB1875(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let t = (2_405_889.258_55 - 2_451_545.0) / 36525
        let arcsec = Double.pi / 180 / 3600
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsec
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsec
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsec
        let (cz, sz, ct, st, cZ, sZ) = (cos(zeta), sin(zeta), cos(theta), sin(theta), cos(z), sin(z))
        return SIMD3(
            (cz * ct * cZ - sz * sZ) * v.x + (-sz * ct * cZ - cz * sZ) * v.y + (-st * cZ) * v.z,
            (cz * ct * sZ + sz * cZ) * v.x + (-sz * ct * sZ + cz * cZ) * v.y + (-st * sZ) * v.z,
            (cz * st) * v.x + (-sz * st) * v.y + ct * v.z
        )
    }

    /// Angle between two directions, in degrees.
    static func separation(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        acos(max(-1, min(1, simd_dot(simd_normalize(a), simd_normalize(b))))) * 180 / .pi
    }
}
