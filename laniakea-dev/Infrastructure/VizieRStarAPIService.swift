import Foundation

/// Naked-eye stars (magnitude ≤ 6) from the Yale Bright Star Catalogue, 5th edition (VizieR V/50),
/// queried through the CDS VizieR TAP API (no key needed). The catalog doesn't change, so a result
/// is kept for 30 days.
class VizieRStarAPIService: StarRepo {
    private static let endpoint = URL(string: "https://tapvizier.cds.unistra.fr/TAPVizieR/tap/sync")!
    private static let query = #"SELECT RAJ2000, DEJ2000, Vmag, "B-V" FROM "V/50/catalog" WHERE Vmag <= 6"#

    private let cache = DiskCache<[Star]>(name: "vizier-bright-stars")

    func loadStars() async throws -> [Star] {
        if let fresh = cache.load(maxAge: 30 * 86400) { return fresh }
        do {
            let stars = try await fetchStars()
            cache.save(stars)
            return stars
        } catch {
            if let stale = cache.load() { return stale }
            throw error
        }
    }

    private struct Response: Decodable {
        let data: [[Double?]]
    }

    private func fetchStars() async throws -> [Star] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "REQUEST", value: "doQuery"),
            URLQueryItem(name: "LANG", value: "ADQL"),
            URLQueryItem(name: "FORMAT", value: "json"),
            URLQueryItem(name: "QUERY", value: Self.query),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // Rows missing a position, magnitude or color (a few novae and non-stellar entries) are skipped.
        return try JSONDecoder().decode(Response.self, from: data).data.compactMap { row in
            guard row.count == 4, let ra = row[0], let dec = row[1], let mag = row[2], let bv = row[3] else { return nil }
            return Star(raDeg: ra, decDeg: dec, magnitude: mag, bv: bv)
        }
    }
}
