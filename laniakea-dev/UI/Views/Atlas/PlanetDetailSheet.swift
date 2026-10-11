import SwiftUI

struct PlanetDetailSheet: View {
    let planet: Planet
    let distanceFromSunAU: Double?
    let distanceFromEarthAU: Double?
    let distanceDateLabel: String

    private static let kmPerAU = 149_597_870.7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(planet.name)
                        .font(.system(size: 30, weight: .bold))
                    Text(planet.summary)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if distanceFromSunAU != nil || distanceFromEarthAU != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(distanceDateLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                        if let sun = distanceFromSunAU {
                            row("From the Sun", Self.distanceText(au: sun))
                        }
                        if let earth = distanceFromEarthAU {
                            row("From Earth", Self.distanceText(au: earth))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    fact("Diameter", "\(Self.number(planet.diameterKm)) km")
                    fact("Mass", "\(planet.massE24Kg.formatted(.number.precision(.significantDigits(3)))) × 10²⁴ kg")
                    fact("Surface gravity", "\(Self.number(planet.gravity, digits: 1)) m/s²")
                    fact("Length of day", Self.duration(hours: planet.lengthOfDayHours))
                    fact("Length of year", Self.duration(hours: planet.orbitalPeriodDays * 24))
                    fact("Average temperature", "\(Self.number(planet.meanTemperatureC)) °C")
                    fact("Moons", "\(planet.moons)")
                    fact("Axial tilt", "\(Self.number(planet.axialTiltDeg, digits: 1))°")
                }

                Text("Source: NASA Planetary Fact Sheet")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 15))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 1))
    }

    private static func distanceText(au: Double) -> String {
        let millionKm = au * kmPerAU / 1_000_000
        return "\(number(millionKm)) million km (\(number(au, digits: 2)) au)"
    }

    private static func duration(hours: Double) -> String {
        if hours < 48 { return "\(number(hours, digits: 1)) hours" }
        let days = hours / 24
        if days < 1000 { return "\(number(days)) Earth days" }
        return "\(number(days / 365.25, digits: 1)) Earth years"
    }

    private static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
