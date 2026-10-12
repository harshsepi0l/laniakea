import Foundation
import simd

/// The sky as seen from one place at one moment. Directions are unit vectors in the local frame
/// Core Motion calls `xTrueNorthZVertical`: x toward true north, y toward west, z straight up.
struct LocalSky {
    let latitudeDeg: Double
    /// East positive.
    let longitudeDeg: Double
    let date: Date

    private let julianDay: Double
    private let localSiderealDeg: Double

    init(latitudeDeg: Double, longitudeDeg: Double, date: Date) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.date = date
        julianDay = OrbitalElements.julianDay(date)
        localSiderealDeg = Self.greenwichSiderealDeg(julianDay: julianDay) + longitudeDeg
    }

    /// Greenwich mean sidereal time in degrees (IAU 1982, Meeus eq. 12.4).
    static func greenwichSiderealDeg(julianDay jd: Double) -> Double {
        let t = (jd - 2_451_545.0) / 36525
        let gmst = 280.460_618_37 + 360.985_647_366_29 * (jd - 2_451_545.0) + 0.000_387_933 * t * t - t * t * t / 38_710_000
        return gmst.truncatingRemainder(dividingBy: 360) + (gmst < 0 ? 360 : 0)
    }

    /// Where a J2000 equatorial direction appears in this sky, precessed to today. Refraction near the
    /// horizon (about half a degree) is ignored.
    func direction(ofEquatorialJ2000 v: SIMD3<Double>) -> SIMD3<Double> {
        let now = SkyCoordinates.precess(v, toJulianDay: julianDay)
        let eq = SkyCoordinates.spherical(now)
        let hourAngle = (localSiderealDeg - eq.l) * .pi / 180
        let dec = eq.b * .pi / 180, lat = latitudeDeg * .pi / 180
        let altitude = asin(sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(hourAngle))
        // Azimuth from north toward east.
        let azimuth = atan2(-sin(hourAngle) * cos(dec), cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(hourAngle))
        return Self.direction(altitude: altitude, azimuth: azimuth)
    }

    /// The same change of frame as `direction(ofEquatorialJ2000:)` as one matrix: precession and
    /// the turn to the local horizon are both rotations, so applying it to a J2000 direction gives
    /// the same answer far faster for thousands of stars.
    var fromJ2000: simd_double3x3 {
        simd_double3x3(columns: (
            direction(ofEquatorialJ2000: SIMD3(1, 0, 0)),
            direction(ofEquatorialJ2000: SIMD3(0, 1, 0)),
            direction(ofEquatorialJ2000: SIMD3(0, 0, 1))
        ))
    }

    func direction(raDeg: Double, decDeg: Double) -> SIMD3<Double> {
        direction(ofEquatorialJ2000: SkyCoordinates.cartesian(longitudeDeg: raDeg, latitudeDeg: decDeg, distance: 1))
    }

    /// Altitude and azimuth in radians to a unit vector: x north, y west, z up.
    static func direction(altitude: Double, azimuth: Double) -> SIMD3<Double> {
        SIMD3(cos(altitude) * cos(azimuth), -cos(altitude) * sin(azimuth), sin(altitude))
    }

    /// Altitude and azimuth (north = 0, east = 90) in degrees of a local direction.
    static func altitudeAzimuth(_ v: SIMD3<Double>) -> (altitude: Double, azimuth: Double) {
        let az = atan2(-v.y, v.x) * 180 / .pi
        return (asin(max(-1, min(1, v.z))) * 180 / .pi, az < 0 ? az + 360 : az)
    }

    /// The local direction back to J2000 equatorial, for asking what lies in a direction (the
    /// corner map's view wedge).
    func equatorialJ2000(ofDirection v: SIMD3<Double>) -> SIMD3<Double> {
        let (altDeg, azDeg) = Self.altitudeAzimuth(v)
        let alt = altDeg * .pi / 180, az = azDeg * .pi / 180, lat = latitudeDeg * .pi / 180
        let dec = asin(sin(alt) * sin(lat) + cos(alt) * cos(lat) * cos(az))
        let hourAngle = atan2(-sin(az) * cos(alt), cos(lat) * sin(alt) - sin(lat) * cos(alt) * cos(az))
        let ra = localSiderealDeg * .pi / 180 - hourAngle
        let ofDate = SkyCoordinates.cartesian(longitudeDeg: ra * 180 / .pi, latitudeDeg: dec * 180 / .pi, distance: 1)
        // Undo precession to the date by precessing back (accurate enough for a wedge).
        let forward = SkyCoordinates.precess(ofDate, toJulianDay: julianDay)
        return simd_normalize(ofDate * 2 - forward)
    }
}
