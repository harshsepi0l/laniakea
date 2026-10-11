import Foundation

/// Reads stars.json: the naked-eye stars (magnitude ≤ 6) from d3-celestial, as [raDeg, decDeg, mag, bv] rows.
class BundleStarRepo: StarRepo {
    private struct File: Decodable {
        let stars: [[Double]]
    }

    func loadStars() throws -> [Star] {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).stars.compactMap { row in
            guard row.count == 4 else { return nil }
            return Star(raDeg: row[0], decDeg: row[1], magnitude: row[2], bv: row[3])
        }
    }
}
