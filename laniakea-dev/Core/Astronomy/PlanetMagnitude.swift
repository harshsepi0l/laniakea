import Foundation
import simd

/// How bright the planets look from Earth (apparent V magnitude), from the formulas JPL Horizons and
/// the Astronomical Almanac use: Mallama & Hilton 2018, "Computing apparent planetary magnitudes for
/// The Astronomical Almanac", Astronomy and Computing 25, 10. Each planet's brightness falls with its
/// distances from the Sun and from Earth and changes with its phase angle (Sun–planet–Earth); Saturn's
/// also depends on how open its rings are, and Uranus's on which latitude faces us.
///
/// Small terms the paper adds are left out: Mars's seasonal and rotational corrections (≲0.1 mag)
/// and Neptune's slow brightening before 2000.
enum PlanetMagnitude {
    /// Apparent V magnitude of a planet (Horizons ID "199"…"899") from heliocentric J2000 ecliptic
    /// positions in au; nil for Earth or an unknown ID.
    static func apparent(planetID: String, heliocentric planet: SIMD3<Double>, earth: SIMD3<Double>) -> Double? {
        let toEarth = earth - planet
        let r = simd_length(planet), delta = simd_length(toEarth)
        guard r > 0, delta > 0 else { return nil }
        let cosPhase = simd_dot(-planet, toEarth) / (r * delta)
        let a = acos(max(-1, min(1, cosPhase))) * 180 / .pi
        let distance = 5 * log10(r * delta)

        switch planetID {
        case "199":
            return distance - 0.613 + 6.3280e-2 * a - 1.6336e-3 * pow(a, 2) + 3.3644e-5 * pow(a, 3)
                - 3.4265e-7 * pow(a, 4) + 1.6893e-9 * pow(a, 5) - 3.0334e-12 * pow(a, 6)
        case "299":
            // A second curve covers the thin crescent near inferior conjunction.
            return a <= 163.7
                ? distance - 4.384 - 1.044e-3 * a + 3.687e-4 * pow(a, 2) - 2.814e-6 * pow(a, 3) + 8.938e-9 * pow(a, 4)
                : distance + 240.44228 - 2.81914 * a + 8.39034e-3 * pow(a, 2)
        case "499":
            return a <= 50
                ? distance - 1.601 + 2.267e-2 * a - 1.302e-4 * pow(a, 2)
                : distance - 0.367 - 2.573e-2 * a + 3.445e-4 * pow(a, 2)
        case "599":
            return distance - 9.395 - 3.7e-4 * a + 6.16e-4 * pow(a, 2)
        case "699":
            // Globe and rings together; the rings lie in Saturn's equator, so their tilt toward us
            // is the sub-Earth latitude.
            let tilt = abs(latitude(facing: -toEarth, pole: saturnPole)) * .pi / 180
            return distance - 8.914 - 1.825 * sin(tilt) + 2.6e-2 * a - 0.378 * sin(tilt) * exp(-2.25 * a)
        case "799":
            // Uranus's poles are brighter than its equator; the paper uses the mean of the
            // sub-Earth and sub-solar latitudes.
            let lat = (abs(latitude(facing: -toEarth, pole: uranusPole)) + abs(latitude(facing: planet, pole: uranusPole))) / 2
            return distance - 7.110 - 8.4e-4 * lat + 6.587e-3 * a + 1.045e-4 * pow(a, 2)
        case "899":
            return distance - 7.00 + 7.944e-3 * a + 9.617e-5 * pow(a, 2)
        default:
            return nil
        }
    }

    /// North poles in J2000 equatorial coordinates (IAU WGCCRE 2015; Archinal et al. 2018,
    /// Celestial Mechanics and Dynamical Astronomy 130, 22).
    private static let saturnPole = SkyCoordinates.cartesian(longitudeDeg: 40.589, latitudeDeg: 83.537, distance: 1)
    private static let uranusPole = SkyCoordinates.cartesian(longitudeDeg: 257.311, latitudeDeg: -15.175, distance: 1)

    /// Latitude on the planet (degrees) of the point facing a viewer who sees it along `sightline`
    /// (an ecliptic vector from the viewer to the planet).
    private static func latitude(facing sightline: SIMD3<Double>, pole: SIMD3<Double>) -> Double {
        let toViewer = -SkyCoordinates.equatorial(ecliptic: sightline)
        return asin(max(-1, min(1, simd_dot(toViewer, pole)))) * 180 / .pi
    }
}
