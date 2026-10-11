import Foundation

/// A planet as JPL Horizons describes it. Physical facts are optional because Horizons formats each
/// body's data sheet a little differently and a value can be missing.
struct Planet: Codable, Identifiable, Equatable {
    /// Horizons body ID, e.g. "399" for Earth.
    let id: String
    let name: String
    let orbit: OrbitalElements
    let meanRadiusKm: Double?
    let massKg: Double?
    let densityGramsPerCm3: Double?
    let surfaceGravity: Double?
    let rotationPeriodHours: Double?
    let temperatureK: Double?
    /// Giant planets have no surface, so Horizons gives their temperature at the 1-bar pressure level.
    let temperatureIsAtOneBar: Bool
    let axialTiltDeg: Double?

    static let earthID = "399"
}
