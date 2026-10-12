import Combine
import Foundation

/// Where the user is in Atlas and the data for each place, loaded from the catalog on first visit.
@MainActor
final class CosmosViewModel: ObservableObject {
    /// From the outside in; the last entry is on screen. Starts at home, the Solar System.
    @Published private(set) var path: [AtlasPlace] = [.laniakea, .milkyWay, .solarSystem]
    @Published private(set) var scenes: [AtlasPlace: GraphScene] = [:]
    @Published private(set) var exoplanets: [StarSystem: [Exoplanet]] = [:]
    @Published private(set) var errors: [AtlasPlace: String] = [:]
    /// Kinds reset when you move to another place; the constellation stays.
    @Published var filter = AtlasFilter() {
        didSet { if filter != oldValue { visibilityCache = [:] } }
    }
    @Published private(set) var boundaries: ConstellationBoundaries?
    /// Each node's constellation abbreviation, per place, once the boundaries have loaded.
    @Published private(set) var nodeConstellations: [AtlasPlace: [String?]] = [:] {
        didSet { visibilityCache = [:] }
    }
    /// `visibility(for:)` is read on every redraw while panning, so it's kept until the filter or
    /// constellations change.
    private var visibilityCache: [AtlasPlace: [Bool]] = [:]
    /// The Sun's surface temperature from JPL Horizons, which sets its color everywhere.
    @Published private(set) var sunTemperatureK: Double?
    private var loading = Set<AtlasPlace>()

    let exoplanetClock = SimulationClock()
    private let repo: CosmicRepo

    init(repo: CosmicRepo) {
        self.repo = repo
    }

    var current: AtlasPlace { path[path.count - 1] }

    func open(_ place: AtlasPlace) {
        filter.kinds = []
        if let index = path.firstIndex(of: place) {
            path = Array(path.prefix(through: index))
        } else {
            path.append(place)
        }
        load(place)
    }

    /// Jumps back to a place in the breadcrumb.
    func goBack(to index: Int) {
        guard path.indices.contains(index) else { return }
        filter.kinds = []
        path = Array(path.prefix(through: index))
        load(current)
    }

    func showLaniakea() {
        filter.kinds = []
        path = [.laniakea]
        load(.laniakea)
    }

    func load(_ place: AtlasPlace) {
        guard scenes[place] == nil, !loading.contains(place) else { return }
        if case .starSystem(let system) = place, exoplanets[system] != nil { return }
        if place == .solarSystem { return }
        loading.insert(place)
        errors[place] = nil
        let repo = repo
        Task {
            defer { loading.remove(place) }
            do {
                switch place {
                case .laniakea:
                    let map = try await repo.laniakea()
                    setScene(await Task.detached { GraphBuilder.laniakea(map) }.value, for: place)
                case .group(let group):
                    let galaxies = try await repo.galaxies(in: group)
                    let spiral = try? await repo.galaxyColors().typical[.spiral]
                    let milkyWay = spiral.map { GalaxyColor(bMinusV: $0, isMeasured: false, typeName: "spiral") }
                    setScene(GraphBuilder.group(group, galaxies: galaxies, milkyWayColor: milkyWay), for: place)
                case .milkyWay:
                    async let systemsTask = repo.starSystems()
                    async let sunTask = try? repo.sun().effectiveTemperatureK
                    // The naked-eye stars are extra; the map still opens without them.
                    async let nakedEyeTask = try? repo.nakedEyeStars()
                    let (systems, sun, nakedEye) = try await (systemsTask, sunTask, nakedEyeTask)
                    sunTemperatureK = sun ?? sunTemperatureK
                    setScene(await Task.detached {
                        GraphBuilder.milkyWay(systems, nakedEye: nakedEye ?? [], sunTemperatureK: sun)
                    }.value, for: place)
                case .starSystem(let system):
                    exoplanets[system] = try await repo.planets(of: system)
                case .solarSystem:
                    break
                }
            } catch {
                errors[place] = (error as? LocalizedError)?.errorDescription ?? "This couldn't be loaded. Check your connection and try again."
            }
        }
    }

    private func setScene(_ scene: GraphScene, for place: AtlasPlace) {
        scenes[place] = scene
        locateConstellations(for: place)
    }

    func loadSun() {
        guard sunTemperatureK == nil else { return }
        let repo = repo
        Task { sunTemperatureK = try? await repo.sun().effectiveTemperatureK }
    }

    /// Loads the IAU constellation boundaries once; filtering by constellation waits for them.
    func loadConstellations() {
        guard boundaries == nil else { return }
        let repo = repo
        Task {
            guard let loaded = try? await repo.constellations() else { return }
            boundaries = loaded
            for place in scenes.keys { locateConstellations(for: place) }
        }
    }

    private func locateConstellations(for place: AtlasPlace) {
        guard let boundaries, let scene = scenes[place], nodeConstellations[place] == nil else { return }
        let directions = scene.nodes.map(\.direction)
        Task {
            nodeConstellations[place] = await Task.detached {
                directions.map { $0.flatMap(boundaries.constellation(of:)) }
            }.value
        }
    }

    // MARK: Filtering

    /// Which of a place's nodes the filter shows, or nil when everything shows. Where you are always shows.
    func visibility(for place: AtlasPlace) -> [Bool]? {
        guard filter.isActive, let scene = scenes[place] else { return nil }
        if let cached = visibilityCache[place] { return cached }
        let constellations = nodeConstellations[place]
        let visible = scene.nodes.indices.map { i in
            scene.nodes[i].isHere || filter.allows(kinds: scene.nodes[i].kinds, constellation: constellations?[i] ?? nil)
        }
        visibilityCache[place] = visible
        return visible
    }

    /// Kinds at a place, with how many objects of each pass the constellation filter.
    func kindCounts(for place: AtlasPlace) -> [(kind: ObjectKind, count: Int)] {
        if case .starSystem(let system) = place {
            return ObjectKind.counts(exoplanets[system]?.map { ObjectKind.planet(radiusEarths: $0.radiusEarths) } ?? [])
        }
        guard let scene = scenes[place] else { return [] }
        let constellations = nodeConstellations[place]
        let kinds = scene.nodes.indices.flatMap { i -> [ObjectKind] in
            guard filter.constellation == nil || constellations?[i] == filter.constellation else { return [] }
            return scene.nodes[i].kinds
        }
        return ObjectKind.counts(kinds)
    }

    /// Constellations at a place, with how many objects in each pass the kind filter.
    func constellationCounts(for place: AtlasPlace) -> [(abbreviation: String, count: Int)] {
        guard let scene = scenes[place], let constellations = nodeConstellations[place] else { return [] }
        var counts: [String: Int] = [:]
        for (node, constellation) in zip(scene.nodes, constellations) {
            guard let constellation, filter.allows(kinds: node.kinds, constellation: nil) else { continue }
            counts[constellation, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { Constellation.name($0.0) < Constellation.name($1.0) }
    }

    func retry() {
        errors[current] = nil
        load(current)
    }
}
