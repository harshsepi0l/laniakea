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
            case .milkyWay:
                async let systems = repo.starSystems()
                async let sun = repo.sun()
                async let colors = repo.galaxyColors()
                data.systems = try await systems
                data.sun = try? await sun
                data.galaxyColors = try? await colors
            case .starSystem(let s):
                data.starDetails = try await repo.details(of: s)
            case .sun:
                data.sun = try await repo.sun()
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Some facts couldn't be loaded. Check your connection and try again."
        }
        data.boundaries = await boundaries
    }
}
