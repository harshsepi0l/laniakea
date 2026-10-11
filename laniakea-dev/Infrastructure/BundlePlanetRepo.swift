import Foundation

/// Reads planets.json, built from the NASA Planetary Fact Sheet and shipped in the app bundle.
class BundlePlanetRepo: PlanetRepo {
    private struct File: Decodable {
        let planets: [Planet]
    }

    func loadPlanets() throws -> [Planet] {
        guard let url = Bundle.main.url(forResource: "planets", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).planets
    }
}
