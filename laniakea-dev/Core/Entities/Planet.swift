import Foundation

struct Planet: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let diameterKm: Double
    let massE24Kg: Double
    let gravity: Double
    let lengthOfDayHours: Double
    let orbitalPeriodDays: Double
    let meanDistanceMillionKm: Double
    let meanTemperatureC: Double
    let moons: Int
    let hasRings: Bool
    let axialTiltDeg: Double
}
