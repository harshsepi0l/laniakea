import Combine
import Foundation

/// Moons for the planet and dwarf-planet cards: the names of every moon Horizons knows, and the
/// orbits and data of the larger ones, loaded when a card opens (one Horizons request per moon).
@MainActor
final class MoonsViewModel: ObservableObject {
    @Published private(set) var listings: [String: [MoonListing]] = [:]
    /// Loaded moons by Horizons ID.
    @Published private(set) var loaded: [String: Moon] = [:]
    @Published private(set) var loadingPrimaries: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let repo: SolarSystemBodiesRepo

    init(repo: SolarSystemBodiesRepo = CosmicCatalog.shared) {
        self.repo = repo
    }

    /// The moons drawn on each card. Not astronomy data, a choice of what to draw: the round moons
    /// (and Pluto's whole family), which all have their size measured. Every other known moon is
    /// listed by name and loads when tapped.
    static let drawn: [String: [String]] = [
        "399": ["301"],
        "499": ["401", "402"],
        "599": ["501", "502", "503", "504"],
        "699": ["601", "602", "603", "604", "605", "606", "608"],
        "799": ["705", "701", "702", "703", "704"],
        "899": ["801"],
        "999": ["901", "902", "903", "904", "905"],
        "2136199": ["120136199"],
        "2136108": ["120136108", "220136108"],
    ]

    func moons(of primaryID: String) -> [Moon] {
        (Self.drawn[primaryID] ?? []).compactMap { loaded[$0] }
    }

    /// Every moon Horizons names for this body, the drawn ones first.
    func listing(of primaryID: String) -> [MoonListing] {
        let drawn = Self.drawn[primaryID] ?? []
        return (listings[primaryID] ?? []).sorted { a, b in
            let ia = drawn.firstIndex(of: a.id) ?? Int.max, ib = drawn.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return (Int(a.id) ?? 0) < (Int(b.id) ?? 0)
        }
    }

    func load(primaryID: String) {
        guard !loadingPrimaries.contains(primaryID) else { return }
        let wanted = (Self.drawn[primaryID] ?? []).filter { loaded[$0] == nil }
        guard listings.isEmpty || !wanted.isEmpty else { return }
        loadingPrimaries.insert(primaryID)
        errors[primaryID] = nil
        Task {
            defer { loadingPrimaries.remove(primaryID) }
            if listings.isEmpty, let all = try? await repo.moonListings() { listings = all }
            for id in wanted {
                do {
                    loaded[id] = try await repo.moon(id: id)
                } catch {
                    errors[primaryID] = "Some moons couldn't be loaded from NASA JPL. Check your connection and try again."
                }
            }
        }
    }

    func moon(id: String) async -> Moon? {
        if let moon = loaded[id] { return moon }
        let moon = try? await repo.moon(id: id)
        if let moon { loaded[id] = moon }
        return moon
    }
}
