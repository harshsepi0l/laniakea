import Combine
import Foundation

/// Loads what a fact sheet needs from the catalog. The sheet shows what's already known straight
/// away and fills in as the rest arrives.
@MainActor
final class FactSheetViewModel: ObservableObject {
    @Published private(set) var sheet: FactSheet
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    let subject: FactSubject
    private let repo: CosmicRepo
    private var data = FactSheetData()

    init(subject: FactSubject, repo: CosmicRepo) {
        self.subject = subject
        self.repo = repo
        sheet = FactSheetBuilder.sheet(for: subject, data: data)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        // Constellations are a nice-to-have; the sheet works without them.
        async let boundaries = try? repo.constellations()
        defer { sheet = FactSheetBuilder.sheet(for: subject, data: data) }
        do {
            switch subject {
            case .laniakea:
                data.map = try await repo.laniakea()
            case .group(let g):
                data.groupDetails = try await repo.details(of: g)
            case .galaxy(let g, _):
                data.galaxyDetails = try await repo.details(of: g)
            case .localGroup, .localGroupGalaxy:
                data.localGroup = try await repo.localGroup()
            case .milkyWay:
                async let systems = repo.starSystems()
                async let sun = repo.sun()
                async let colors = repo.galaxyColors()
                data.systems = try await systems
                data.sun = try? await sun
                data.galaxyColors = try? await colors
            case .starSystem(let s):
                async let bright = s.hd == nil ? nil : (try? repo.nakedEyeStars())?.first { $0.hd == s.hd }
                data.starDetails = try await repo.details(of: s)
                data.brightStar = await bright
            case .sun:
                data.sun = try await repo.sun()
            case .nakedEyeStar:
                break
            case .constellation(let abbreviation):
                async let starsTask = repo.nakedEyeStars()
                async let systemsTask = try? repo.starSystems()
                async let boundsTask = repo.constellations()
                let (stars, systems, bounds) = try await (starsTask, systemsTask, boundsTask)
                // About 70,000 boundary lookups: keep them off the main thread.
                let (profile, hosts) = await Task.detached { () -> (ConstellationProfile?, Int) in
                    let profile = ConstellationProfile(abbreviation: abbreviation, boundaries: bounds, nakedEye: stars)
                    let hosts = (systems ?? []).filter { bounds.constellation(of: SkyCoordinates.equatorial(galactic: $0.position)) == abbreviation }.count
                    return (profile, hosts)
                }.value
                data.constellation = profile
                data.constellationHosts = systems == nil ? nil : hosts
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Some facts couldn't be loaded. Check your connection and try again."
        }
        data.boundaries = await boundaries
    }
}
