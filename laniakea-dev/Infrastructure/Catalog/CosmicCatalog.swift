import Foundation
import simd

/// The app's one data layer. Every object in Atlas comes from a public API through here, and every
/// result is cached on disk so it still shows offline:
///
/// | Data | Source |
/// |---|---|
/// | Laniakea's boundary | Cosmicflows basins of attraction (Dupuy & Courtois 2023) |
/// | Galaxy groups and galaxies | Cosmicflows-4 (Tully et al. 2023) via VizieR |
/// | Names, Hubble types | SIMBAD |
/// | Galaxy colors | RC3 (de Vaucouleurs et al. 1991) via VizieR |
/// | Stars with planets, and their planets | NASA Exoplanet Archive |
/// | Solar System planets | JPL Horizons |
/// | Naked-eye stars | Yale Bright Star Catalogue via VizieR |
/// | Constellation boundaries | IAU boundaries (Roman 1987) from CDS |
final class CosmicCatalog: CosmicRepo, PlanetRepo, StarRepo {
    static let shared = CosmicCatalog()

    private let horizons = HorizonsPlanetAPIService()
    private let brightStars = VizieRStarAPIService()
    private let boundary = LaniakeaBoundarySource()

    private static let catalogAge: TimeInterval = 180 * 86400
    private static let exoplanetAge: TimeInterval = 7 * 86400

    // MARK: Solar System and stars

    func loadPlanets() async throws -> [Planet] { try await horizons.loadPlanets() }
    func loadStars() async throws -> [Star] { try await brightStars.loadStars() }

    // MARK: Laniakea

    func laniakea() async throws -> LaniakeaMap {
        try await cached(DiskCache<LaniakeaMap>(name: "laniakea-map-v4"), maxAge: Self.catalogAge) {
            async let gridTask = self.boundary.loadGrid()
            async let colorsTask = self.galaxyColors()
            async let rowsTask = TAPClient.vizier.query("""
                SELECT "1PGC", Ngal, DMzp, SGL, SGB, Vh FROM "J/ApJ/944/94/groups" WHERE Dist < 400
                """)
            // VizieR's copy of the group table has wrong sky positions for some groups (Virgo's is
            // 45° off), while every member galaxy's position is right. So each group is placed at the
            // average direction of its members, at the group's distance.
            async let directionsTask = TAPClient.vizier.query("""
                SELECT "1PGC", AVG(COS(RADIANS(SGB))*COS(RADIANS(SGL))) AS ux, \
                AVG(COS(RADIANS(SGB))*SIN(RADIANS(SGL))) AS uy, AVG(SIN(RADIANS(SGB))) AS uz \
                FROM "J/ApJ/944/94/table2" GROUP BY "1PGC"
                """)
            let (grid, rows, directionRows, colors) = try await (gridTask, rowsTask, directionsTask, colorsTask)
            var directions: [Int: SIMD3<Double>] = [:]
            for row in directionRows {
                guard let id = row.int("1PGC"), let x = row.double("ux"), let y = row.double("uy"), let z = row.double("uz"),
                      x != 0 || y != 0 || z != 0
                else { continue }
                directions[id] = simd_normalize(SIMD3(x, y, z))
            }

            struct Candidate { let id: Int; let count: Int; let distance: Double; let position: SIMD3<Double>; let velocity: Double; let edge: Bool }
            let inside: [Candidate] = rows.compactMap { row in
                // Dist is rounded to 0.1 Mpc, too coarse for nearby groups, so use the distance modulus.
                guard let id = row.int("1PGC"), let d = row.double("DMzp").map(SkyCoordinates.megaparsecs(distanceModulus:)) else { return nil }
                let direction = directions[id] ?? {
                    guard let l = row.double("SGL"), let b = row.double("SGB") else { return nil }
                    return SkyCoordinates.cartesian(longitudeDeg: l, latitudeDeg: b, distance: 1)
                }()
                guard let direction else { return nil }
                let p = direction * d
                let isInside = grid.contains(p)
                guard isInside || grid.touches(p) else { return nil }
                return Candidate(id: id, count: row.int("Ngal") ?? 0, distance: d, position: p,
                                 velocity: row.double("Vh") ?? 0, edge: !isInside)
            }

            async let clusterNamesTask = self.namedClusters(for: inside.map { ($0.id, $0.position, $0.velocity, $0.count) })
            async let galaxyNamesTask = self.galaxyNames(pgc: inside.map(\.id))
            // So a group's dot matches its brightest galaxy's color inside the group view.
            async let leaderTypesTask = self.morphologies(pgc: inside.map(\.id))
            let (clusterNames, galaxyNames, leaderTypes) = try await (clusterNamesTask, galaxyNamesTask, leaderTypesTask)

            let groups = inside.map { c -> GalaxyGroup in
                let galaxy = galaxyNames[c.id] ?? "PGC \(c.id)"
                let named = clusterNames[c.id]
                // SIMBAD has no single entry for the Local Group to match, so name it from its leader, Andromeda.
                let name = c.id == GalaxyGroup.localGroupID ? "Local Group" : named?.name ?? (c.count > 1 ? "\(galaxy) group" : galaxy)
                return GalaxyGroup(id: c.id, name: name, galaxyCount: c.count, distanceMpc: c.distance,
                                   position: c.position, isOnBoundary: c.edge, isCluster: named?.isCluster ?? false,
                                   color: colors.color(pgc: c.id, morphology: leaderTypes[c.id]))
            }
            let cells = grid.cellCentres()
            return LaniakeaMap(
                groups: groups, outlineCells: grid.outline(), cellSizeMpc: grid.cellMpc, volumeMpc3: grid.volumeMpc3,
                longestSpanMpc: grid.longestSpan(), centre: cells.reduce(.zero, +) / Double(max(cells.count, 1)),
                milkyWayColor: colors.typical[.spiral].map { GalaxyColor(bMinusV: $0, isMeasured: false, typeName: "spiral") }
            )
        }
    }

    func galaxies(in group: GalaxyGroup) async throws -> [Galaxy] {
        try await cached(DiskCache<[Galaxy]>(name: "cf4-group-v3-\(group.id)"), maxAge: Self.catalogAge) {
            let rows = try await TAPClient.vizier.query("""
                SELECT PGC, DM, e_DM, SGL, SGB FROM "J/ApJ/944/94/table2" WHERE "1PGC" = \(group.id)
                """)
            let ids = rows.compactMap { $0.int("PGC") }
            async let namesTask = self.galaxyNames(pgc: ids)
            async let typesTask = self.morphologies(pgc: ids)
            async let colorsTask = self.galaxyColors()
            let (names, types, colors) = try await (namesTask, typesTask, colorsTask)
            return try Self.nonEmpty("This group's galaxies", rows.compactMap { row in
                guard let id = row.int("PGC"), let dm = row.double("DM"), let l = row.double("SGL"), let b = row.double("SGB")
                else { return nil }
                let d = SkyCoordinates.megaparsecs(distanceModulus: dm)
                return Galaxy(
                    id: id, name: names[id] ?? "PGC \(id)", groupID: group.id, distanceMpc: d,
                    distanceErrorMpc: row.double("e_DM").map { d * log(10) / 5 * $0 },
                    position: SkyCoordinates.cartesian(longitudeDeg: l, latitudeDeg: b, distance: d),
                    morphology: types[id],
                    color: colors.color(pgc: id, morphology: types[id])
                )
            })
        }
    }

    func details(of group: GalaxyGroup) async throws -> GroupDetails {
        try await cached(DiskCache<GroupDetails>(name: "cf4-group-details-v3-\(group.id)"), maxAge: Self.catalogAge) {
            let rows = try await TAPClient.vizier.query("""
                SELECT e_DMzp, fV3k, Vh, Vpec, o_DMcal, o_DMsnIa, o_DMfp, o_DMtf, o_DMsbfo, o_DMsbfi, DMsnII \
                FROM "J/ApJ/944/94/groups" WHERE "1PGC" = \(group.id)
                """)
            guard let row = rows.first else { throw CatalogError.unreadable("This group's Cosmicflows-4 entry") }
            // The catalog counts galaxies per method, except for type II supernovae.
            var methods: [GroupDetails.MethodCount] = []
            let counted: [(DistanceMethod, Int?)] = [
                (.calibrators, row.int("o_DMcal")), (.supernovaIa, row.int("o_DMsnIa")),
                // Optical and infrared counts can include the same galaxy, so take the larger.
                (.surfaceBrightness, max(row.int("o_DMsbfo") ?? 0, row.int("o_DMsbfi") ?? 0)),
                (.tullyFisher, row.int("o_DMtf")), (.fundamentalPlane, row.int("o_DMfp")),
            ]
            for (method, count) in counted where (count ?? 0) > 0 { methods.append(.init(method: method, galaxies: count)) }
            if row.double("DMsnII") != nil { methods.append(.init(method: .supernovaII, galaxies: nil)) }

            let d = group.distanceMpc
            let errorDM = row.double("e_DMzp")
            // Peculiar velocity error from the distance error: δv ≈ v · ln10/5 · δμ.
            let v = row.double("fV3k")
            return GroupDetails(
                distanceErrorMpc: errorDM.map { d * log(10) / 5 * $0 },
                velocityKmS: row.double("Vh"), peculiarVelocityKmS: row.double("Vpec"),
                peculiarVelocityErrorKmS: errorDM.flatMap { e in v.map { abs($0) * log(10) / 5 * e } },
                methods: methods
            )
        }
    }

    func details(of galaxy: Galaxy) async throws -> GalaxyDetails {
        try await cached(DiskCache<GalaxyDetails>(name: "galaxy-details-v2-\(galaxy.id)"), maxAge: Self.catalogAge) {
            async let simbadTask = TAPClient.simbad.query("""
                SELECT b.morph_type, b.galdim_majaxis, b.rvz_radvel FROM basic AS b JOIN ident AS i ON i.oidref = b.oid \
                WHERE i.id = 'PGC \(galaxy.id)'
                """)
            async let cf4Task = TAPClient.vizier.query("""
                SELECT DMsnIa, DMtf, DMfp, DMsbf, DMsnII, DMtrgb, DMceph, DMmas FROM "J/ApJ/944/94/table2" WHERE PGC = \(galaxy.id)
                """)
            let (simbad, cf4) = try await (simbadTask, cf4Task)
            let s = simbad.first, c = cf4.first
            let columns: [(String, DistanceMethod)] = [
                ("DMceph", .cepheids), ("DMtrgb", .redGiants), ("DMmas", .masers), ("DMsnIa", .supernovaIa),
                ("DMsnII", .supernovaII), ("DMsbf", .surfaceBrightness), ("DMtf", .tullyFisher), ("DMfp", .fundamentalPlane),
            ]
            return GalaxyDetails(
                morphology: s?["morph_type"].flatMap { $0.isEmpty ? nil : $0 },
                majorAxisArcmin: s?.double("galdim_majaxis"),
                velocityKmS: s?.double("rvz_radvel"),
                methods: columns.compactMap { c?.double($0.0) != nil ? $0.1 : nil }
            )
        }
    }

    // MARK: Exoplanets

    func starSystems() async throws -> [StarSystem] {
        try await cached(DiskCache<[StarSystem]>(name: "exoplanet-hosts-v2"), maxAge: Self.exoplanetAge) {
            // One row per star. sy_pnum counts planets around every star in a multiple system (55 Cnc B
            // would show 7), so count each star's own planets instead.
            let rows = try await TAPClient.exoplanetArchive.query("""
                select hostname, avg(ra) as ra, avg(dec) as dec, max(sy_dist) as sy_dist, count(*) as planets, \
                max(st_spectype) as st_spectype, max(st_teff) as st_teff from pscomppars where sy_dist is not null group by hostname
                """)
            return try Self.nonEmpty("Stars with planets", rows.compactMap { row in
                guard let name = row["hostname"], !name.isEmpty,
                      let ra = row.double("ra"), let dec = row.double("dec"), let d = row.double("sy_dist")
                else { return nil }
                let g = SkyCoordinates.galactic(raDeg: ra, decDeg: dec)
                return StarSystem(
                    id: name, name: name, distanceParsecs: d, planetCount: row.int("planets") ?? 1,
                    spectralType: row["st_spectype"].flatMap { $0.isEmpty ? nil : $0 },
                    temperatureK: row.double("st_teff"),
                    position: SkyCoordinates.cartesian(longitudeDeg: g.l, latitudeDeg: g.b, distance: d)
                )
            })
        }
    }

    func planets(of system: StarSystem) async throws -> [Exoplanet] {
        let key = system.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return try await cached(DiskCache<[Exoplanet]>(name: "exoplanets-v4-\(key)"), maxAge: Self.exoplanetAge) {
            let host = system.id.replacingOccurrences(of: "'", with: "''")
            let rows = try await TAPClient.exoplanetArchive.query("""
                select pl_name, pl_orbsmax, pl_orbper, pl_orbeccen, pl_rade, pl_rade_reflink, pl_bmasse, pl_bmassprov, pl_tranmid, pl_eqt, pl_insol, disc_year, discoverymethod \
                from pscomppars where hostname = '\(host)'
                """)
            return try Self.nonEmpty("\(system.name)'s planets", rows.compactMap { row in
                guard let name = row["pl_name"], !name.isEmpty else { return nil }
                return Exoplanet(
                    id: name, name: name, semiMajorAxisAU: row.double("pl_orbsmax"), periodDays: row.double("pl_orbper"),
                    eccentricity: row.double("pl_orbeccen"), radiusEarths: row.double("pl_rade"),
                    radiusIsEstimate: row["pl_rade_reflink"]?.contains("CALCULATED"),
                    massEarths: row.double("pl_bmasse"), massIsMinimum: row["pl_bmassprov"].map { $0 == "Msini" },
                    massIsEstimate: row["pl_bmassprov"].map { $0 == "M-R relationship" },
                    transitMidpointJD: row.double("pl_tranmid"),
                    equilibriumTempK: row.double("pl_eqt"), insolationEarths: row.double("pl_insol"),
                    discoveryYear: row.int("disc_year"), discoveryMethod: row["discoverymethod"]
                )
            }
            .sorted { ($0.semiMajorAxisAU ?? .infinity) < ($1.semiMajorAxisAU ?? .infinity) })
        }
    }

    func details(of system: StarSystem) async throws -> StarDetails {
        let key = system.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return try await cached(DiskCache<StarDetails>(name: "star-details-\(key)"), maxAge: Self.exoplanetAge) {
            let host = system.id.replacingOccurrences(of: "'", with: "''")
            let rows = try await TAPClient.exoplanetArchive.query("""
                select st_spectype, st_teff, st_rad, st_mass, st_age, st_met, st_lum, sy_vmag, sy_snum \
                from pscomppars where hostname = '\(host)'
                """)
            guard let row = rows.first else { throw CatalogError.unreadable("\(system.name)'s entry") }
            return StarDetails(
                spectralType: row["st_spectype"].flatMap { $0.isEmpty ? nil : $0 }, temperatureK: row.double("st_teff"),
                radiusSuns: row.double("st_rad"), massSuns: row.double("st_mass"), ageGyr: row.double("st_age"),
                logLuminositySuns: row.double("st_lum"), metallicity: row.double("st_met"),
                apparentMagnitude: row.double("sy_vmag"), starCount: row.int("sy_snum")
            )
        }
    }

    // MARK: Sun and constellations

    func sun() async throws -> SunDetails {
        try await cached(DiskCache<SunDetails>(name: "horizons-sun"), maxAge: Self.catalogAge) {
            try await self.horizons.loadSun()
        }
    }

    func constellations() async throws -> ConstellationBoundaries {
        try await cached(DiskCache<ConstellationBoundaries>(name: "iau-constellations"), maxAge: 365 * 86400) {
            let url = URL(string: "https://cdsarc.cds.unistra.fr/ftp/VI/42/data.dat")!
            let (data, response) = try await URLSession.shared.data(from: url)
            let boundaries = ConstellationBoundaries.parse(String(decoding: data, as: UTF8.self))
            guard (response as? HTTPURLResponse)?.statusCode == 200, boundaries.edges.count > 300 else {
                throw CatalogError.unreadable("The constellation boundaries")
            }
            return boundaries
        }
    }

    // MARK: Galaxy colors

    func galaxyColors() async throws -> GalaxyColors {
        try await cached(DiskCache<GalaxyColors>(name: "rc3-colors"), maxAge: Self.catalogAge) {
            let rows = try await TAPClient.vizier.query("""
                SELECT PGC, T, "B-VoT" FROM "VII/155/rc3" WHERE T IS NOT NULL OR "B-VoT" IS NOT NULL
                """)
            var measured: [Int: Double] = [:], types: [Int: GalaxyType] = [:], samples: [GalaxyType: [Double]] = [:]
            for row in rows {
                // RC3 writes "PGC 2557" or "PGC11598".
                guard let id = row["PGC"].flatMap({ Int($0.filter(\.isNumber)) }) else { continue }
                let type = row.double("T").flatMap(GalaxyType.init(rc3Stage:))
                let bv = row.double("B-VoT")
                if let type { types[id] = type }
                if let bv { measured[id] = bv }
                if let type, let bv { samples[type, default: []].append(bv) }
            }
            let typical = samples.mapValues { values in values.sorted()[values.count / 2] }
            guard !measured.isEmpty, typical[.spiral] != nil else { throw CatalogError.unreadable("RC3 galaxy colors") }
            return GalaxyColors(measured: measured, types: types, typical: typical)
        }
    }

    // MARK: Names from SIMBAD

    /// Hubble types (such as "SA(s)b") from SIMBAD, by PGC number.
    private func morphologies(pgc: [Int]) async throws -> [Int: String] {
        var types: [Int: String] = [:]
        for chunk in stride(from: 0, to: pgc.count, by: 300).map({ Array(pgc[$0..<min($0 + 300, pgc.count)]) }) {
            let ids = chunk.map { "'PGC \($0)'" }.joined(separator: ",")
            let rows = try await TAPClient.simbad.query("""
                SELECT i.id AS pgc, b.morph_type FROM ident AS i JOIN basic AS b ON b.oid = i.oidref \
                WHERE i.id IN (\(ids)) AND b.morph_type IS NOT NULL
                """)
            for row in rows {
                guard let text = row["pgc"], let id = Int(text.filter(\.isNumber)), let type = row["morph_type"], !type.isEmpty else { continue }
                types[id] = type
            }
        }
        return types
    }

    /// Best common name for each galaxy: a proper name such as "Andromeda Galaxy", then Messier, NGC,
    /// IC and UGC numbers.
    private func galaxyNames(pgc: [Int]) async throws -> [Int: String] {
        var names: [Int: (rank: Int, name: String)] = [:]
        for chunk in stride(from: 0, to: pgc.count, by: 300).map({ Array(pgc[$0..<min($0 + 300, pgc.count)]) }) {
            let ids = chunk.map { "'PGC \($0)'" }.joined(separator: ",")
            let rows = try await TAPClient.simbad.query("""
                SELECT i1.id AS pgc, i2.id AS name FROM ident AS i1 JOIN ident AS i2 ON i1.oidref = i2.oidref \
                WHERE i1.id IN (\(ids)) AND (i2.id LIKE 'NAME %' OR i2.id LIKE 'M %' OR i2.id LIKE 'NGC %' \
                OR i2.id LIKE 'IC %' OR i2.id LIKE 'UGC %')
                """)
            for row in rows {
                guard let pgcText = row["pgc"], let id = Int(pgcText.filter(\.isNumber)), let raw = row["name"] else { continue }
                let name = raw.split(separator: " ").joined(separator: " ")
                let (rank, display) = Self.rank(name)
                if let current = names[id], current.rank < rank || (current.rank == rank && current.name.count >= display.count) { continue }
                names[id] = (rank, display)
            }
        }
        return names.mapValues(\.name)
    }

    private static func rank(_ name: String) -> (Int, String) {
        if name.hasPrefix("NAME ") {
            let proper = String(name.dropFirst(5))
            return (proper.contains("Galaxy") || proper.contains("Cloud") ? 0 : 2, proper)
        }
        if name.hasPrefix("M ") { return (1, name) }
        if name.hasPrefix("NGC ") { return (3, name) }
        if name.hasPrefix("IC ") { return (4, name) }
        return (5, name)
    }

    /// Matches groups to SIMBAD's named clusters and groups (such as "Virgo Cluster") by direction
    /// and velocity. Each name goes to at most one group: clusters before groups, then the richest
    /// group nearby, then the closest.
    private func namedClusters(for groups: [(id: Int, position: SIMD3<Double>, velocity: Double, count: Int)]) async throws -> [Int: (name: String, isCluster: Bool)] {
        // Many famous clusters are filed under a catalog number (the Centaurus Cluster is ACO 3526),
        // so look for proper names among each cluster's identifiers.
        let rows = try await TAPClient.simbad.query("""
            SELECT b.main_id, i.id AS name, b.ra, b.dec, b.rvz_redshift, b.otype FROM basic AS b \
            JOIN ident AS i ON i.oidref = b.oid \
            WHERE b.otype IN ('ClG', 'GrG') AND i.id LIKE 'NAME %' AND b.rvz_redshift < 0.05
            """)

        // One entry per cluster: its main name if that is a proper name, else its longest alias
        // ("Fornax Cluster" over "For Cluster").
        struct Cluster { var name: String; let direction: SIMD3<Double>; let velocity: Double; let isCluster: Bool }
        var clusters: [String: Cluster] = [:]
        for row in rows {
            guard let main = row["main_id"], let raw = row["name"], let ra = row.double("ra"), let dec = row.double("dec"),
                  let z = row.double("rvz_redshift")
            else { continue }
            let tidy = { (s: String) in String(s.dropFirst(5)).split(separator: " ").joined(separator: " ") }
            let alias = tidy(raw)
            if var existing = clusters[main] {
                if !main.hasPrefix("NAME "), alias.count > existing.name.count { existing.name = alias; clusters[main] = existing }
            } else {
                clusters[main] = Cluster(
                    name: main.hasPrefix("NAME ") ? tidy(main) : alias,
                    direction: SkyCoordinates.supergalacticDirection(raDeg: ra, decDeg: dec),
                    velocity: z * 299_792.458, isCluster: row["otype"] == "ClG"
                )
            }
        }

        struct Match { let group: Int; let count: Int; let cluster: String; let name: String; let isCluster: Bool; let separation: Double }
        var matches: [Match] = []
        for (key, cluster) in clusters {
            for g in groups where abs(g.velocity - cluster.velocity) < 700 {
                let separation = SkyCoordinates.separation(cluster.direction, g.position)
                if separation < 2 {
                    matches.append(Match(group: g.id, count: g.count, cluster: key, name: cluster.name,
                                         isCluster: cluster.isCluster, separation: separation))
                }
            }
        }
        var result: [Int: (name: String, isCluster: Bool)] = [:]
        var used = Set<String>()
        for m in matches.sorted(by: { ($0.isCluster ? 0 : 1, -$0.count, $0.separation) < ($1.isCluster ? 0 : 1, -$1.count, $1.separation) })
        where result[m.group] == nil && !used.contains(m.cluster) && !result.values.contains(where: { $0.name == m.name }) {
            result[m.group] = (m.name, m.isCluster)
            used.insert(m.cluster)
        }
        return result
    }

    // MARK: Caching

    /// Every group, host star and planet list has at least one entry, so an empty result means the
    /// query went wrong; throwing keeps it out of the cache.
    private static func nonEmpty<T>(_ what: String, _ items: [T]) throws -> [T] {
        guard !items.isEmpty else { throw CatalogError.unreadable(what) }
        return items
    }

    /// A fresh cached value, else a new fetch (saved), else a stale cached value.
    private func cached<T: Codable>(_ cache: DiskCache<T>, maxAge: TimeInterval, fetch: () async throws -> T) async throws -> T {
        if let fresh = cache.load(maxAge: maxAge) { return fresh }
        do {
            let value = try await fetch()
            cache.save(value)
            return value
        } catch {
            if let stale = cache.load() { return stale }
            throw error
        }
    }
}
