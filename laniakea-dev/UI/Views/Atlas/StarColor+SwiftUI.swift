import SwiftUI

extension StarColor.RGB {
    /// On a light background the palest stars would vanish, so colors are darkened there.
    func color(dark: Bool) -> Color {
        dark ? Color(red: r, green: g, blue: b) : Color(red: r * 0.78, green: g * 0.72, blue: b * 0.72)
    }
}

extension StarColor {
    /// A star's color from its temperature, or neutral grey when the temperature isn't known.
    static func swiftUI(temperature: Double?, dark: Bool) -> Color {
        guard let temperature else { return Color(white: dark ? 0.62 : 0.42) }
        return color(temperature: temperature).color(dark: dark)
    }
}

extension PlanetComposition {
    func swiftUI(dark: Bool) -> Color {
        let c = color(dark: dark)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

extension Optional where Wrapped == PlanetComposition {
    /// A planet's color, or plain ink when its makeup isn't known.
    func swiftUI(dark: Bool) -> Color {
        self?.swiftUI(dark: dark) ?? (dark ? .white : Color(white: 0.07))
    }
}
