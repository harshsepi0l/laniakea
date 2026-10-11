import Combine
import simd
import Foundation

class SolarSystemViewModel: ObservableObject {
    @Published private(set) var planets: [Planet] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
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
        guard planets.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            defer { isLoading = false }
            do {
                planets = try await repo.loadPlanets()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Planet data couldn't be loaded from NASA JPL. Check your connection and try again."
            }
        }
    }

    func planets(matching query: String) -> [Planet] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return planets.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Distance from the Sun at the selection date, in au.
    func distanceFromSun(_ planet: Planet) -> Double? {
        simd_length(planet.orbit.position(at: selectionDate))
    }

    /// Distance from Earth at the selection date, in au.
    func distanceFromEarth(_ planet: Planet) -> Double? {
        guard planet.id != Planet.earthID,
              let earth = planets.first(where: { $0.id == Planet.earthID })
        else { return nil }
        return simd_length(planet.orbit.position(at: selectionDate) - earth.orbit.position(at: selectionDate))
    }
}
