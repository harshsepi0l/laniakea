import Foundation

/// The Cosmicflows-4 velocity and density fields (Courtois et al. 2023), as published by the
/// Cosmicflows project: two FITS cubes, 3 MB and 1 MB.
struct CosmicFlowSource {
    static let velocityURL = URL(string: "https://projets.ip2i.in2p3.fr/cosmicflows/CF4_new_64-z008_velocity.fits")!
    static let densityURL = URL(string: "https://projets.ip2i.in2p3.fr/cosmicflows/CF4_new_64-z008_delta.fits")!

    func loadField() async throws -> CosmicFlowField {
        async let velocityTask = fetch(Self.velocityURL)
        async let densityTask = fetch(Self.densityURL)
        let (velocityData, densityData) = try await (velocityTask, densityTask)
        let n = CosmicFlowField.size
        let cell = n * n * n
        // The velocity cube's slowest axis holds the components, in grid-axis order: z, y, x.
        let velocity = try Self.floats(fits: velocityData, count: 3 * cell, name: "The Cosmicflows velocity field")
        let density = try Self.floats(fits: densityData, count: cell, name: "The Cosmicflows density field")
        return CosmicFlowField(
            vx: Array(velocity[(2 * cell)..<(3 * cell)]), vy: Array(velocity[cell..<(2 * cell)]),
            vz: Array(velocity[0..<cell]), density: density
        )
    }

    /// The big-endian 32-bit floats after a FITS header.
    static func floats(fits: Data, count: Int, name: String) throws -> [Float] {
        let block = 2880
        var offset = 0
        var found = false
        headerLoop: while offset + block <= fits.count {
            for card in stride(from: offset, to: offset + block, by: 80) {
                let key = String(decoding: fits[(fits.startIndex + card)..<(fits.startIndex + card + 8)], as: UTF8.self)
                if key.trimmingCharacters(in: .whitespaces) == "END" { found = true; offset += block; break headerLoop }
            }
            offset += block
        }
        guard found, fits.count >= offset + count * 4 else { throw CatalogError.unreadable(name) }
        return fits.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            return (0..<count).map { i in
                Float(bitPattern: UInt32(bigEndian: base.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
            }
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogError.badResponse(url.host ?? "") }
        return data
    }
}
