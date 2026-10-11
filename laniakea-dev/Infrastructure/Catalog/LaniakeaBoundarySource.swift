import Foundation
import simd

/// Laniakea's boundary from the Cosmicflows project's published basins of attraction
/// (Dupuy & Courtois 2023, A&A 678, A176): a 128³ grid over 1000 Mpc/h, centred on us, where each
/// cell holds the number of the basin it belongs to. Laniakea is basin 1.
///
/// The grid ships inside a 67 MB zip alongside three other grids. The zip stores its files
/// uncompressed and the server accepts byte ranges, so only the one 16 MB grid is downloaded.
struct LaniakeaBoundarySource {
    static let archiveURL = URL(string: "https://projets.ip2i.in2p3.fr/cosmicflows/CF4_new_128-z008_watersheds-fits.zip")!
    static let gridFile = "CF4_new_128-z008_BoA.fits"
    static let laniakeaLabel = 1.0
    static let boxMpcPerH = 1000.0
    /// Cosmicflows-4 distances assume H0 = 75 km/s/Mpc.
    static let h = 0.75

    struct Grid {
        let size: Int
        /// Flat indices (z, y, x order, as stored) of Laniakea's cells.
        let cells: Set<Int>

        var cellMpc: Double { LaniakeaBoundarySource.boxMpcPerH / Double(size) / LaniakeaBoundarySource.h }

        /// Whether a supergalactic position (Mpc, Milky Way at the origin) lies inside Laniakea.
        func contains(_ p: SIMD3<Double>) -> Bool {
            guard let index = index(of: p) else { return false }
            return cells.contains(index)
        }

        /// Whether a position is outside Laniakea but in a cell touching it.
        func touches(_ p: SIMD3<Double>) -> Bool {
            guard let index = index(of: p) else { return false }
            let x = index % size, y = (index / size) % size, z = index / (size * size)
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 {
                let (nx, ny, nz) = (x + dx, y + dy, z + dz)
                guard (0..<size).contains(nx), (0..<size).contains(ny), (0..<size).contains(nz) else { continue }
                if cells.contains((nz * size + ny) * size + nx) { return true }
            } } }
            return false
        }

        /// Cell centres seen from above (supergalactic x, y), in Mpc.
        func outline() -> [SIMD2<Double>] {
            var seen = Set<Int>()
            var result: [SIMD2<Double>] = []
            for index in cells {
                let x = index % size, y = (index / size) % size
                if seen.insert(y * size + x).inserted {
                    result.append(SIMD2(centre(x), centre(y)))
                }
            }
            return result
        }

        var volumeMpc3: Double { Double(cells.count) * pow(cellMpc, 3) }

        /// Supergalactic positions of all of Laniakea's cell centres, in Mpc.
        func cellCentres() -> [SIMD3<Double>] {
            cells.map { index in
                SIMD3(centre(index % size), centre((index / size) % size), centre(index / (size * size)))
            }
        }

        /// The widest distance across Laniakea, edge to edge, in Mpc.
        func longestSpan() -> Double {
            let points = cellCentres()
            var longest = 0.0
            for i in points.indices {
                for j in (i + 1)..<points.count {
                    longest = max(longest, simd_distance_squared(points[i], points[j]))
                }
            }
            return longest.squareRoot() + cellMpc
        }

        private func centre(_ i: Int) -> Double {
            (Double(i) + 0.5) * cellMpc - Double(size) * cellMpc / 2
        }

        private func index(of p: SIMD3<Double>) -> Int? {
            let half = Double(size) * cellMpc / 2
            let i = [p.x, p.y, p.z].map { Int(floor(($0 + half) / cellMpc)) }
            guard i.allSatisfy({ (0..<size).contains($0) }) else { return nil }
            return (i[2] * size + i[1]) * size + i[0]
        }
    }

    func loadGrid() async throws -> Grid {
        let range = try await locateGridFile()
        let fits = try await fetch(range: range)
        return try Self.parseLaniakeaCells(fits: fits)
    }

    /// Finds the grid's byte range in the zip by reading the central directory at the end of the archive.
    private func locateGridFile() async throws -> ClosedRange<Int> {
        let tail = try await fetch(suffix: 4096)
        guard let eocd = tail.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06])) else {
            throw CatalogError.unreadable("The Laniakea boundary archive")
        }
        let e = eocd.lowerBound
        let entryCount = Int(tail.uint16(at: e + 10))
        let directoryOffset = Int(tail.uint32(at: e + 16))
        let directorySize = Int(tail.uint32(at: e + 12))
        let directory = try await fetch(range: directoryOffset...(directoryOffset + directorySize - 1))

        var p = 0
        for _ in 0..<entryCount {
            guard directory.uint32(at: p) == 0x02014B50 else { break }
            let method = directory.uint16(at: p + 10)
            let size = Int(directory.uint32(at: p + 20))
            let nameLength = Int(directory.uint16(at: p + 28))
            let extraLength = Int(directory.uint16(at: p + 30))
            let commentLength = Int(directory.uint16(at: p + 32))
            let localOffset = Int(directory.uint32(at: p + 42))
            let name = String(decoding: directory[(directory.startIndex + p + 46)..<(directory.startIndex + p + 46 + nameLength)], as: UTF8.self)
            if name == Self.gridFile, method == 0 {
                // The local header repeats the name and may carry a different extra field.
                let local = try await fetch(range: localOffset...(localOffset + 29))
                let start = localOffset + 30 + Int(local.uint16(at: 26)) + Int(local.uint16(at: 28))
                return start...(start + size - 1)
            }
            p += 46 + nameLength + extraLength + commentLength
        }
        throw CatalogError.unreadable("The Laniakea boundary archive")
    }

    /// Reads a FITS cube of big-endian doubles and returns the cells labelled as Laniakea.
    static func parseLaniakeaCells(fits: Data) throws -> Grid {
        let block = 2880
        var header: [String: String] = [:]
        var offset = 0
        headerLoop: while offset + block <= fits.count {
            for card in stride(from: offset, to: offset + block, by: 80) {
                let text = String(decoding: fits[(fits.startIndex + card)..<(fits.startIndex + card + 80)], as: UTF8.self)
                let key = text.prefix(8).trimmingCharacters(in: .whitespaces)
                if key == "END" { offset += block; break headerLoop }
                if let eq = text.firstIndex(of: "="), text.distance(from: text.startIndex, to: eq) == 8 {
                    header[key] = text[text.index(after: eq)...].split(separator: "/").first?
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            offset += block
        }
        guard header["BITPIX"] == "-64",
              let n = header["NAXIS1"].flatMap(Int.init), header["NAXIS2"] == "\(n)", header["NAXIS3"] == "\(n)",
              fits.count >= offset + n * n * n * 8
        else { throw CatalogError.unreadable("The Laniakea boundary grid") }

        var cells = Set<Int>()
        fits.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            for i in 0..<(n * n * n) {
                let bits = UInt64(bigEndian: base.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
                if Double(bitPattern: bits) == laniakeaLabel { cells.insert(i) }
            }
        }
        return Grid(size: n, cells: cells)
    }

    private func fetch(range: ClosedRange<Int>) async throws -> Data {
        try await fetch(header: "bytes=\(range.lowerBound)-\(range.upperBound)", expected: range.count)
    }

    private func fetch(suffix: Int) async throws -> Data {
        try await fetch(header: "bytes=-\(suffix)", expected: nil)
    }

    private func fetch(header: String, expected: Int?) async throws -> Data {
        var request = URLRequest(url: Self.archiveURL)
        request.setValue(header, forHTTPHeaderField: "Range")
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 206, expected == nil || data.count == expected else {
            throw CatalogError.badResponse(Self.archiveURL.host ?? "")
        }
        return data
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }
}
