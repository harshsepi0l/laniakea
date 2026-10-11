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
                    Text(orbitSummary)
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
                    if let radius = planet.meanRadiusKm {
                        fact("Diameter", "\(Self.number(radius * 2)) km")
                    }
                    if let mass = planet.massKg {
                        fact("Mass", Self.scientific(mass, unit: "kg"))
                    }
                    if let gravity = planet.surfaceGravity {
                        fact(planet.temperatureIsAtOneBar ? "Gravity (cloud tops)" : "Surface gravity", "\(Self.number(gravity, digits: 1)) m/s²")
                    }
                    if let density = planet.densityGramsPerCm3 {
                        fact("Density", "\(Self.number(density, digits: 2)) g/cm³")
                    }
                    if let rotation = planet.rotationPeriodHours {
                        fact("Spins once every", Self.duration(hours: rotation))
                    }
                    fact("Length of year", Self.duration(hours: planet.orbit.periodDays * 24))
                    if let kelvin = planet.temperatureK {
                        fact(planet.temperatureIsAtOneBar ? "Temperature (cloud tops)" : "Average temperature", "\(Self.number(kelvin - 273.15)) °C")
                    }
                    if let tilt = planet.axialTiltDeg {
                        fact("Axial tilt", "\(Self.number(tilt, digits: tilt < 1 ? 2 : 1))°")
                    }
                }

                Text("Source: NASA JPL Horizons")
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

    private var orbitSummary: String {
        let millionKm = planet.orbit.semiMajorAxisAU * Self.kmPerAU / 1_000_000
        return "Orbits the Sun every \(Self.duration(hours: planet.orbit.periodDays * 24)), "
            + "at an average distance of \(Self.number(millionKm)) million km."
    }

    /// e.g. 5.97 × 10²⁴ kg
    private static func scientific(_ value: Double, unit: String) -> String {
        let exponent = Int(floor(log10(value)))
        let mantissa = value / pow(10, Double(exponent))
        let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        let power = String(String(exponent).compactMap { superscripts[$0] })
        return "\(number(mantissa, digits: 2)) × 10\(power) \(unit)"
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
