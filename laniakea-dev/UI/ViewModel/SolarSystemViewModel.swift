import Combine
import simd
import Foundation

class SolarSystemViewModel: ObservableObject {
    @Published private(set) var planets: [Planet] = []
    /// Pluto, Ceres, Eris, Haumea and Makemake; empty until loaded, and the planets show without them.
    @Published private(set) var dwarfPlanets: [DwarfPlanet] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var selectedPlanet: Planet?
    private(set) var selectionDate = Date()
    let clock = SimulationClock()
    let moons: MoonsViewModel

    /// Planets and dwarf planets together, in order from the Sun.
    var bodies: [Planet] {
        (planets + dwarfPlanets.map(\.planet)).sorted { $0.orbit.semiMajorAxisAU < $1.orbit.semiMajorAxisAU }
    }

    func dwarf(_ planet: Planet) -> DwarfPlanet? { dwarfPlanets.first { $0.id == planet.id } }

    private let repo: PlanetRepo
    private let bodiesRepo: SolarSystemBodiesRepo

    @MainActor
    init(repo: PlanetRepo, bodiesRepo: SolarSystemBodiesRepo = CosmicCatalog.shared) {
        self.repo = repo
        self.bodiesRepo = bodiesRepo
        moons = MoonsViewModel(repo: bodiesRepo)
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
                return
            }
            // After the planets, as Horizons takes one request at a time.
            if dwarfPlanets.isEmpty, let dwarfs = try? await bodiesRepo.dwarfPlanets() { dwarfPlanets = dwarfs }
        }
    }

    func planets(matching query: String) -> [Planet] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return bodies.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
