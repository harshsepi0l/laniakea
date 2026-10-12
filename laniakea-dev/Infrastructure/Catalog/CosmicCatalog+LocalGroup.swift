import Foundation
import simd

/// The Local Group, from the Local Volume Database (Pace 2025), with Hubble types from McConnachie
/// (2012) via VizieR.
extension CosmicCatalog {
    /// The database's combined table from its latest release: dwarfs, star clusters and the big
    /// galaxies they orbit, about 800 kB.
    private static let localVolumeDatabaseURL = URL(string: "https://github.com/apace7/local_volume_database/releases/latest/download/comb_all.csv")!

    func localGroup() async throws -> LocalGroup {
        try await cached(DiskCache<LocalGroup>(name: "local-group-v2"), maxAge: Self.catalogAge) {
            async let tableTask = URLSession.shared.data(from: Self.localVolumeDatabaseURL)
            // Types are a nice-to-have: the Local Group still shows without them.
            async let typesTask = try? TAPClient.vizier.query("""
                SELECT Name, RAJ2000, DEJ2000, MType FROM "J/AJ/144/4/catalog"
                """)
            let ((data, response), typeRows) = try await (tableTask, typesTask)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw CatalogError.badResponse(Self.localVolumeDatabaseURL.host ?? "")
            }
            let text = String(decoding: data, as: UTF8.self)
            // About 1,700 rows: parse off the main thread.
            return try await Task.detached(priority: .userInitiated) {
                try LocalGroupReader(rows: TAPClient.parseCSV(text), types: typeRows ?? []).localGroup()
            }.value
        }
    }

    /// Facts for a Cosmicflows-4 group with no row in the group table, from its galaxies: their
    /// combined distance error and the methods that measured them.
    func memberDetails(of group: GalaxyGroup) async throws -> GroupDetails {
        let rows = try await TAPClient.vizier.query("""
            SELECT e_DM, DMsnIa, DMtf, DMfp, DMsbf, DMsnII, DMtrgb, DMceph, DMmas FROM "J/ApJ/944/94/table2" \
            WHERE "1PGC" = \(group.id)
            """)
        guard !rows.isEmpty else { throw CatalogError.unreadable("This group's Cosmicflows-4 entry") }
        let columns: [(String, DistanceMethod)] = [
            ("DMceph", .cepheids), ("DMtrgb", .redGiants), ("DMmas", .masers), ("DMsnIa", .supernovaIa),
            ("DMsnII", .supernovaII), ("DMsbf", .surfaceBrightness), ("DMtf", .tullyFisher), ("DMfp", .fundamentalPlane),
        ]
        let methods = columns.compactMap { column, method -> GroupDetails.MethodCount? in
            let count = rows.filter { $0.double(column) != nil }.count
            return count > 0 ? .init(method: method, galaxies: count) : nil
        }
        // Inverse-variance mean of the members' distance moduli: its error is 1/√Σ(1/σ²).
        let weights = rows.compactMap { $0.double("e_DM") }.filter { $0 > 0 }.map { 1 / ($0 * $0) }
        let errorDM = weights.isEmpty ? nil : 1 / weights.reduce(0, +).squareRoot()
        return GroupDetails(
            distanceErrorMpc: errorDM.map { group.distanceMpc * log(10) / 5 * $0 },
            velocityKmS: nil, peculiarVelocityKmS: nil, peculiarVelocityErrorKmS: nil, methods: methods
        )
    }
}

/// Picks the Local Group out of the Local Volume Database's combined table.
private struct LocalGroupReader {
    let byKey: [String: TAPClient.Row]
    let types: [(name: String, direction: SIMD3<Double>, type: String)]

    /// Tables of galaxies; the rest hold star clusters and unconfirmed candidates.
    private static let galaxyTables: Set<String> = ["dwarf_mw", "dwarf_m31", "dwarf_local_field", "misc"]
    /// Common names for the biggest five, which the database lists by catalog name or abbreviation.
    private static let commonNames = [
        "mw": "Milky Way", "m_031": "Andromeda Galaxy", "m_033": "Triangulum Galaxy",
        "lmc": "Large Magellanic Cloud", "smc": "Small Magellanic Cloud",
    ]

    init(rows: [TAPClient.Row], types typeRows: [TAPClient.Row]) {
        var byKey: [String: TAPClient.Row] = [:]
        for row in rows { if let key = row["key"], !key.isEmpty { byKey[key] = row } }
        self.byKey = byKey
        types = typeRows.compactMap { row in
            guard let name = row["Name"], let ra = row.double("RAJ2000"), let dec = row.double("DEJ2000"),
                  let type = row["MType"]?.trimmingCharacters(in: .whitespaces), !type.isEmpty, !type.hasPrefix("?")
            else { return nil }
            return (name, SkyCoordinates.cartesian(longitudeDeg: ra, latitudeDeg: dec, distance: 1), type)
        }
    }

    func localGroup() throws -> LocalGroup {
        guard let mw = byKey[LocalGroupGalaxy.milkyWayID], let m31 = byKey[LocalGroupGalaxy.andromedaID],
              let mwRA = mw.double("ra"), let mwDec = mw.double("dec"), let r0 = sunToGalacticCentreKpc(raDeg: mwRA, decDeg: mwDec),
              let m31RA = m31.double("ra"), let m31Dec = m31.double("dec"), let m31D = m31.double("distance"),
              let m31GC = m31.double("distance_gc"), let m31LG = m31.double("distance_lg"), m31GC > 0
        else { throw CatalogError.unreadable("The Local Volume Database") }

        let galacticCentre = SkyCoordinates.supergalacticDirection(raDeg: mwRA, decDeg: mwDec) * r0
        let andromeda = SkyCoordinates.supergalacticDirection(raDeg: m31RA, decDeg: m31Dec) * m31D
        // The database measures distance_lg from a point on the line from the Milky Way's centre to
        // Andromeda's; Andromeda's own two distances say how far along it is.
        let centre = galacticCentre + (andromeda - galacticCentre) * ((m31GC - m31LG) / m31GC)

        var members: [LocalGroupGalaxy] = []
        var candidates = 0
        for (key, row) in byKey where Self.galaxyTables.contains(row["table"] ?? "") {
            let side = side(of: key)
            let isMember = side != .neither || (row.double("distance_lg").map { $0 <= LocalGroup.zeroVelocityRadiusKpc } ?? false)
            guard isMember, let ra = row.double("ra"), let dec = row.double("dec") else { continue }
            guard row["confirmed_galaxy"] == "1" else { candidates += 1; continue }
            let isMilkyWay = key == LocalGroupGalaxy.milkyWayID
            let distance = row.double("distance")
            guard isMilkyWay || distance != nil else { continue }
            let direction = SkyCoordinates.supergalacticDirection(raDeg: ra, decDeg: dec)
            let spread = ((row.double("distance_em") ?? 0) + (row.double("distance_ep") ?? 0)) / 2
            let host = row["host"].flatMap { $0.isEmpty ? nil : $0 }
            members.append(LocalGroupGalaxy(
                id: key, name: displayName(key), side: side, hostID: host, hostName: host.map(displayName),
                distanceKpc: isMilkyWay ? nil : distance, distanceErrorKpc: spread > 0 ? spread : nil,
                distanceFromHostKpc: host == nil ? nil : row.double("distance_host"),
                distanceFromCentreKpc: row.double("distance_lg"),
                position: isMilkyWay ? galacticCentre : direction * (distance ?? 0),
                raDeg: ra, decDeg: dec,
                morphology: morphology(name: row["name"] ?? key, raDeg: ra, decDeg: dec),
                absoluteMagnitudeV: row.double("M_V"), logStellarMass: row.double("mass_stellar"),
                velocityKmS: row.double("vlos_systemic"), halfLightArcmin: row.double("rhalf"),
                distanceSource: row["ref_distance"].flatMap(Self.citation)
            ))
        }
        guard members.count > 50 else { throw CatalogError.unreadable("The Local Group") }
        let order = [LocalGroupGalaxy.milkyWayID, LocalGroupGalaxy.andromedaID]
        members.sort { a, b in
            let (i, j) = (order.firstIndex(of: a.id) ?? 2, order.firstIndex(of: b.id) ?? 2)
            return i != j ? i < j : (a.distanceKpc ?? 0) < (b.distanceKpc ?? 0)
        }
        return LocalGroup(members: members, centre: centre, candidateCount: candidates)
    }

    /// Which big galaxy a dwarf belongs to, following hosts up: the SMC's host is the LMC, whose
    /// host is the Milky Way. Triangulum counts as Andromeda's.
    private func side(of key: String) -> LocalGroupGalaxy.Side {
        var current = key
        var seen = Set<String>()
        while seen.insert(current).inserted {
            if current == LocalGroupGalaxy.milkyWayID { return .milkyWay }
            if current == LocalGroupGalaxy.andromedaID { return .andromeda }
            guard let host = byKey[current]?["host"], !host.isEmpty else { break }
            current = host
        }
        return .neither
    }

    private func displayName(_ key: String) -> String {
        Self.commonNames[key] ?? byKey[key]?["name"] ?? key
    }

    /// The Sun's distance from the Galactic Centre that the database used for its galactocentric
    /// distances (`distance_gc`), so the Milky Way sits where its satellites' distances put it.
    /// Each satellite gives it through the law of cosines; the median shrugs off rounding.
    private func sunToGalacticCentreKpc(raDeg: Double, decDeg: Double) -> Double? {
        let toCentre = SkyCoordinates.supergalacticDirection(raDeg: raDeg, decDeg: decDeg)
        var estimates: [Double] = []
        for row in byKey.values {
            guard let d = row.double("distance"), d > 20, d < 300, let dgc = row.double("distance_gc"),
                  let ra = row.double("ra"), let dec = row.double("dec")
            else { continue }
            let c = simd_dot(SkyCoordinates.supergalacticDirection(raDeg: ra, decDeg: dec), toCentre)
            // dgc² = d² + R² − 2dR·c, solved for R; of the two roots, the Sun is a few kpc out.
            let disc = dgc * dgc - d * d * (1 - c * c)
            guard disc >= 0 else { continue }
            for r in [d * c + disc.squareRoot(), d * c - disc.squareRoot()] where r > 5 && r < 12 { estimates.append(r) }
        }
        guard !estimates.isEmpty else { return nil }
        return estimates.sorted()[estimates.count / 2]
    }

    /// The type McConnachie (2012) gives a galaxy: the entry at its position, or for big galaxies
    /// whose catalogued centres differ by up to a degree (the Magellanic Clouds), the same name nearby.
    private func morphology(name: String, raDeg: Double, decDeg: Double) -> String? {
        let direction = SkyCoordinates.cartesian(longitudeDeg: raDeg, latitudeDeg: decDeg, distance: 1)
        let simple = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let best = types.map { (entry: $0, separation: SkyCoordinates.separation($0.direction, direction)) }
            .min { $0.separation < $1.separation }
        guard let best else { return nil }
        if best.separation < 0.5 { return best.entry.type }
        return types.first { simple($0.name) == simple(name) && SkyCoordinates.separation($0.direction, direction) < 1.5 }?.type
    }

    /// "Savino2022ApJ...938..101S" → "Savino (2022)".
    private static func citation(_ bibcode: String) -> String? {
        guard let match = bibcode.firstMatch(of: #/^([A-Za-z\-']+)(\d{4})/#) else { return nil }
        return "\(match.1) (\(match.2))"
    }
}
