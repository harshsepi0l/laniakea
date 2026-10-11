import Combine
import simd
import Foundation

class SolarSystemViewModel: ObservableObject {
    @Published private(set) var planets: [Planet] = []
    @Published private(set) var errorMessage: String?
    @Published var selectedPlanet: Planet?
    private(set) var selectionDate = Date()
    let clock = SimulationClock()

    private let repo: PlanetRepo

    init(repo: PlanetRepo) {
        self.repo = repo
    }

    func select(_ planet: Planet) {
        selectionDate = clock.simulatedDate
        selectedPlanet = planet
    }

    var selectionDateLabel: String {
        Calendar.current.isDateInToday(selectionDate)
            ? "Right now"
            : "On \(selectionDate.formatted(date: .abbreviated, time: .omitted))"
    }

    func load() {
        guard planets.isEmpty else { return }
        do {
            planets = try repo.loadPlanets()
        } catch {
            errorMessage = "Planet data couldn't be loaded."
        }
    }

    func planets(matching query: String) -> [Planet] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return planets.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Distance from the Sun at the selection date, in au.
    func distanceFromSun(_ planet: Planet) -> Double? {
        PlanetEphemeris.position(of: planet.id, at: selectionDate).map { simd_length($0) }
    }

    /// Distance from Earth at the selection date, in au.
    func distanceFromEarth(_ planet: Planet) -> Double? {
        guard planet.id != "earth",
              let p = PlanetEphemeris.position(of: planet.id, at: selectionDate),
              let earth = PlanetEphemeris.position(of: "earth", at: selectionDate)
        else { return nil }
        return simd_length(p - earth)
    }
}
