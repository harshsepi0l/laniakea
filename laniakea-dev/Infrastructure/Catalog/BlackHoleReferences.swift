import Foundation

/// The few black-hole values no queryable catalog holds, taken from the papers that measured them.
///
/// Everything else about black holes comes live from catalogs (positions from SIMBAD and Gaia,
/// stellar black holes from BlackCAT, galaxy black holes from van den Bosch 2016). These are the
/// exceptions the owner approved: each is the published value with its full citation, kept here
/// in one place so they're easy to check and update when a better measurement appears.
enum BlackHoleReferences {
    /// A published value with its uncertainty and where it comes from.
    struct Value {
        let value: Double
        let plus: Double
        let minus: Double
        let citation: String
    }

    // MARK: Sagittarius A*

    /// The Sun's distance from Sagittarius A*, R0, in parsecs, from the orbits of four stars around
    /// it tracked with VLTI/GRAVITY. Statistical error ±9 pc; the paper puts the systematic error at
    /// ≈ 30 pc, and the two are combined here in quadrature (≈ 31 pc).
    /// GRAVITY Collaboration (Abuter R. et al.) 2022, A&A 657, L12, "Mass distribution in the
    /// Galactic Center based on interferometric astrometry of multiple stellar orbits".
    static let sgrADistance = Value(value: 8277, plus: 31, minus: 31,
                                    citation: "GRAVITY Collaboration 2022, A&A 657, L12")

    /// Sagittarius A*'s mass in Suns from the same fit: (4.297 ± 0.012 stat ± ≈ 0.040 sys) × 10⁶,
    /// combined in quadrature. Same paper as `sgrADistance`.
    static let sgrAMass = Value(value: 4.297e6, plus: 0.042e6, minus: 0.042e6,
                                citation: "GRAVITY Collaboration 2022, A&A 657, L12")

    /// The mass the Event Horizon Telescope found from the size of the ring in its 2017 image,
    /// 4.0 (+1.1 −0.6) × 10⁶ Suns, consistent with the star orbits.
    /// Event Horizon Telescope Collaboration 2022, ApJL 930, L12, "First Sagittarius A* Event
    /// Horizon Telescope Results. I."
    static let sgrAImageMass = Value(value: 4.0e6, plus: 1.1e6, minus: 0.6e6,
                                     citation: "Event Horizon Telescope Collaboration 2022, ApJL 930, L12")

    // MARK: M87*

    /// M87*'s mass from the size of its shadow in the first black-hole image, (6.5 ± 0.2 stat ±
    /// 0.7 sys) × 10⁹ Suns, shown alongside van den Bosch's gas-dynamics value (log M = 9.58),
    /// which is lower: the two methods disagree, and both are published.
    /// Event Horizon Telescope Collaboration 2019, ApJL 875, L6, "First M87 Event Horizon
    /// Telescope Results. VI. The Shadow and Mass of the Central Black Hole".
    static let m87ImageMass = Value(value: 6.5e9, plus: 0.7e9, minus: 0.7e9,
                                    citation: "Event Horizon Telescope Collaboration 2019, ApJL 875, L6")
    /// van den Bosch (2016) lists M87 under this name.
    static let m87CatalogName = "NGC4486"

    // MARK: Stellar black holes

    /// Masses of the dormant black holes Gaia found by the wobble of their companion stars, from the
    /// discovery papers' joint fits of Gaia astrometry and ground-based radial velocities. Keyed by
    /// Gaia DR3 source_id of the visible star.
    /// - Gaia BH1: El-Badry K. et al. 2023, MNRAS 518, 1057, "A Sun-like star orbiting a black hole".
    /// - Gaia BH2: El-Badry K. et al. 2023, MNRAS 521, 4323, "A red giant orbiting a black hole".
    /// - Gaia BH3: Gaia Collaboration (Panuzzo P. et al.) 2024, A&A 686, L2, "Discovery of a
    ///   dormant 33 solar-mass black hole in pre-release Gaia astrometry".
    static let gaiaMasses: [Int: Value] = [
        4373465352415301632: Value(value: 9.62, plus: 0.18, minus: 0.18, citation: "El-Badry et al. 2023, MNRAS 518, 1057"),
        5870569352746779008: Value(value: 8.94, plus: 0.34, minus: 0.34, citation: "El-Badry et al. 2023, MNRAS 521, 4323"),
        4318465066420528000: Value(value: 32.70, plus: 0.82, minus: 0.82, citation: "Gaia Collaboration, Panuzzo et al. 2024, A&A 686, L2"),
    ]

    /// Gaia BH3's distance in parsecs. Gaia DR3 has no orbit solution for it (it came from
    /// pre-release DR4 data), and its DR3 single-star parallax is thrown off by the orbit, so the
    /// discovery paper's adopted distance is used. Panuzzo et al. 2024, A&A 686, L2.
    static let gaiaBH3Distance = Value(value: 590.6, plus: 5.8, minus: 5.8,
                                       citation: "Gaia Collaboration, Panuzzo et al. 2024, A&A 686, L2")

    /// Cygnus X-1's mass, 21.2 ± 2.2 Suns, from its companion's orbit with the VLBA parallax
    /// distance. Miller-Jones J. C. A. et al. 2021, Science 371, 1046, "Cygnus X-1 contains a
    /// 21-solar mass black hole".
    static let cygX1Mass = Value(value: 21.2, plus: 2.2, minus: 2.2,
                                 citation: "Miller-Jones et al. 2021, Science 371, 1046")
}
