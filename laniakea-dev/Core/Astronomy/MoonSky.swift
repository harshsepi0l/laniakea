import Foundation
import simd

/// The Moon's geocentric position from JPL Horizons, sampled hourly (astrometric, ICRF/J2000
/// equatorial, km). Only geocentric positions are asked for, so your location never leaves the
/// device: the shift to where you stand (up to about 1°) is applied here.
struct MoonEphemeris: Codable, Equatable {
    struct Sample: Codable, Equatable {
        /// Julian day on Horizons' TDB scale.
        let julianDayTDB: Double
        let x: Double, y: Double, z: Double
    }
    let samples: [Sample]

    /// TT − UTC: 32.184 s plus the 37 leap seconds in force since 2017 (IERS Bulletin C). TDB differs
    /// from TT by under 2 ms.
    static let ttMinusUTCSeconds = 69.184

    /// Geocentric position at a date in km, interpolated between the hourly samples. Over an hour the
    /// Moon's path bends away from a straight line by about 4 km, a few thousandths of a degree.
    /// Nil outside the sampled span: the Moon isn't extrapolated.
    func geocentric(at date: Date) -> SIMD3<Double>? {
        let jd = OrbitalElements.julianDay(date) + Self.ttMinusUTCSeconds / 86400
        guard let upper = samples.firstIndex(where: { $0.julianDayTDB >= jd }), upper > 0 else {
            if let first = samples.first, abs(first.julianDayTDB - jd) < 1e-9 { return SIMD3(first.x, first.y, first.z) }
            return nil
        }
        let a = samples[upper - 1], b = samples[upper]
        let f = (jd - a.julianDayTDB) / (b.julianDayTDB - a.julianDayTDB)
        return SIMD3(a.x, a.y, a.z) + (SIMD3(b.x, b.y, b.z) - SIMD3(a.x, a.y, a.z)) * f
    }
}

/// The Moon as seen from one place at one moment.
struct MoonView: Equatable {
    /// Topocentric J2000 equatorial unit vector.
    let equatorial: SIMD3<Double>
    /// Distance from you, km.
    let distanceKm: Double
    /// Distance from Earth's centre, km.
    let geocentricDistanceKm: Double
    /// Fraction of the disc lit, 0 to 1.
    let illuminatedFraction: Double
    /// Sun–Moon–Earth angle, degrees.
    let phaseAngleDeg: Double
    /// The Moon's ecliptic longitude minus the Sun's, 0…360°: 0 new, 90 first quarter, 180 full.
    let elongationDeg: Double
    /// Angular radius, degrees.
    let angularRadiusDeg: Double

    static let radiusKm = 1737.4

    var isWaxing: Bool { elongationDeg < 180 }

    /// The phase's name. The principal phases are the instants when the Moon's longitude is 0°, 90°,
    /// 180° or 270° from the Sun's (Meeus, Astronomical Algorithms, ch. 49); within about 15 hours of
    /// one (±7.5°), the Moon is given that phase's name.
    var phaseName: String {
        switch elongationDeg {
        case ..<7.5, 352.5...: return "New moon"
        case ..<82.5: return "Waxing crescent"
        case ..<97.5: return "First quarter"
        case ..<172.5: return "Waxing gibbous"
        case ..<187.5: return "Full moon"
        case ..<262.5: return "Waning gibbous"
        case ..<277.5: return "Last quarter"
        default: return "Waning crescent"
        }
    }
}

enum MoonSky {
    /// Earth's equatorial radius and flattening factor b/a (IAU 1976, as in Meeus ch. 11).
    private static let earthRadiusKm = 6378.14
    private static let polarRatio = 0.996_647_19

    /// Where you are relative to Earth's centre, in km, J2000 equatorial. Geodetic latitude to
    /// geocentric with Meeus eq. 11.1; turned with mean sidereal time (Meeus eq. 12.4) and taken back
    /// from the equator of date to J2000 by undoing IAU 1976 precession.
    static func observer(latitudeDeg: Double, longitudeDeg: Double, altitudeM: Double = 0, date: Date) -> SIMD3<Double> {
        let phi = latitudeDeg * .pi / 180
        let u = atan(polarRatio * tan(phi))
        let h = altitudeM / 1000 / earthRadiusKm
        let rhoSin = polarRatio * sin(u) + h * sin(phi)
        let rhoCos = cos(u) + h * cos(phi)
        let jd = OrbitalElements.julianDay(date)
        let theta = (LocalSky.greenwichSiderealDeg(julianDay: jd) + longitudeDeg) * .pi / 180
        let ofDate = SIMD3(rhoCos * cos(theta), rhoCos * sin(theta), rhoSin) * earthRadiusKm
        // Precession is a rotation, so its inverse is its transpose.
        let m = simd_double3x3(columns: (
            SkyCoordinates.precess(SIMD3(1, 0, 0), toJulianDay: jd),
            SkyCoordinates.precess(SIMD3(0, 1, 0), toJulianDay: jd),
            SkyCoordinates.precess(SIMD3(0, 0, 1), toJulianDay: jd)
        ))
        return m.transpose * ofDate
    }

    /// The Moon from where you stand. `sunGeocentric` is the Sun's position from Earth in J2000
    /// ecliptic au (minus Earth's heliocentric position). The phase angle and lit fraction follow
    /// Meeus eqs. 48.2–48.3 and 48.1.
    static func view(ephemeris: MoonEphemeris, sunGeocentric: SIMD3<Double>, latitudeDeg: Double, longitudeDeg: Double,
                     altitudeM: Double = 0, date: Date) -> MoonView? {
        guard let geo = ephemeris.geocentric(at: date) else { return nil }
        let topo = geo - observer(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg, altitudeM: altitudeM, date: date)
        let sunEq = SkyCoordinates.equatorial(ecliptic: sunGeocentric)
        let sunKm = simd_length(sunGeocentric) * Moon.kmPerAU
        let delta = simd_length(geo)
        let psi = acos(max(-1, min(1, simd_dot(simd_normalize(geo), sunEq))))
        let phaseAngle = atan2(sunKm * sin(psi), delta - sunKm * cos(psi))
        let moonLongitude = SkyCoordinates.spherical(ecliptic(equatorial: geo)).l
        let sunLongitude = SkyCoordinates.spherical(sunGeocentric).l
        var elongation = (moonLongitude - sunLongitude).truncatingRemainder(dividingBy: 360)
        if elongation < 0 { elongation += 360 }
        let distance = simd_length(topo)
        return MoonView(
            equatorial: simd_normalize(topo), distanceKm: distance, geocentricDistanceKm: delta,
            illuminatedFraction: (1 + cos(phaseAngle)) / 2, phaseAngleDeg: phaseAngle * 180 / .pi,
            elongationDeg: elongation, angularRadiusDeg: asin(MoonView.radiusKm / distance) * 180 / .pi
        )
    }

    /// The next moonrise and moonset within `hours`, found by stepping ten minutes at a time and
    /// interpolating. The Moon rises when its upper limb meets the horizon, with 34′ of refraction
    /// (Meeus ch. 15; the U.S. Naval Observatory's definition); its altitude here is topocentric.
    static func nextRiseAndSet(ephemeris: MoonEphemeris, latitudeDeg: Double, longitudeDeg: Double,
                               from start: Date, hours: Double = 26) -> (rise: Date?, set: Date?) {
        func height(_ date: Date) -> Double? {
            guard let geo = ephemeris.geocentric(at: date) else { return nil }
            let topo = geo - observer(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg, date: date)
            let sky = LocalSky(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg, date: date)
            let altitude = LocalSky.altitudeAzimuth(sky.direction(ofEquatorialJ2000: simd_normalize(topo))).altitude
            let semidiameter = asin(MoonView.radiusKm / simd_length(topo)) * 180 / .pi
            return altitude + 34.0 / 60 + semidiameter
        }
        var rise: Date?, set: Date?
        let step: TimeInterval = 600
        var t = start
        guard var previous = height(t) else { return (nil, nil) }
        while t.timeIntervalSince(start) < hours * 3600, rise == nil || set == nil {
            let next = t.addingTimeInterval(step)
            guard let h = height(next) else { break }
            if (previous < 0) != (h < 0) {
                let crossing = t.addingTimeInterval(step * previous / (previous - h))
                if h > 0, rise == nil { rise = crossing }
                if h < 0, set == nil { set = crossing }
            }
            previous = h
            t = next
        }
        return (rise, set)
    }

    /// J2000 equatorial to J2000 ecliptic (the inverse of `SkyCoordinates.equatorial(ecliptic:)`).
    static func ecliptic(equatorial v: SIMD3<Double>) -> SIMD3<Double> {
        let e = 23.4392911 * Double.pi / 180
        return SIMD3(v.x, v.y * cos(e) + v.z * sin(e), -v.y * sin(e) + v.z * cos(e))
    }
}
