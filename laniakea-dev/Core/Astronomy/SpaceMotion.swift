import Foundation
import simd

/// How things move through space, from what's measured. Used to run Atlas forward and back in time.
enum SpaceMotion {
    /// km/s to parsecs per year.
    static let parsecsPerYearPerKmS = 1.0227e-6
    /// km/s to megaparsecs per year.
    static let megaparsecsPerYearPerKmS = 1.0227e-12
    /// Cosmicflows-4's Hubble constant, 75 km/s/Mpc (Tully et al. 2023), as a growth rate per year.
    static let expansionPerYear = 75 * megaparsecsPerYearPerKmS

    /// A star's velocity relative to the Sun in Galactic Cartesian km/s (x toward the Galactic
    /// Centre, z toward Galactic north), from its distance, proper motion and radial velocity.
    /// `pmRAMasPerYear` is μα cos δ, as Hipparcos and the Exoplanet Archive give it. Without a radial
    /// velocity only the motion across the sky is known, and that's all this returns.
    static func galacticVelocity(raDeg: Double, decDeg: Double, distanceParsecs d: Double,
                                 pmRAMasPerYear: Double, pmDecMasPerYear: Double, radialVelocityKmS: Double?) -> SIMD3<Double> {
        let ra = raDeg * .pi / 180, dec = decDeg * .pi / 180
        let outward = SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
        let east = SIMD3(-sin(ra), cos(ra), 0)
        let north = SIMD3(-sin(dec) * cos(ra), -sin(dec) * sin(ra), cos(dec))
        // 4.74047 km/s is one AU per year: an arcsecond a year at one parsec.
        let k = 4.740_47 * d / 1000
        let equatorial = outward * (radialVelocityKmS ?? 0) + east * (k * pmRAMasPerYear) + north * (k * pmDecMasPerYear)
        return SkyCoordinates.galactic(equatorial: equatorial)
    }
}

extension NakedEyeStar {
    /// Velocity relative to the Sun in Galactic km/s; nil without a distance and proper motion.
    var velocityKmS: SIMD3<Double>? {
        guard let d = distanceParsecs, let pmRA = pmRAMasPerYear, let pmDec = pmDecMasPerYear else { return nil }
        return SpaceMotion.galacticVelocity(raDeg: raDeg, decDeg: decDeg, distanceParsecs: d,
                                            pmRAMasPerYear: pmRA, pmDecMasPerYear: pmDec, radialVelocityKmS: radialVelocityKmS)
    }
}

extension StarSystem {
    /// Velocity relative to the Sun in Galactic km/s; nil without a proper motion.
    var velocityKmS: SIMD3<Double>? {
        guard let pmRA = pmRAMasPerYear, let pmDec = pmDecMasPerYear else { return nil }
        let eq = SkyCoordinates.spherical(SkyCoordinates.equatorial(galactic: position))
        return SpaceMotion.galacticVelocity(raDeg: eq.l, decDeg: eq.b, distanceParsecs: distanceParsecs,
                                            pmRAMasPerYear: pmRA, pmDecMasPerYear: pmDec, radialVelocityKmS: radialVelocityKmS)
    }
}
