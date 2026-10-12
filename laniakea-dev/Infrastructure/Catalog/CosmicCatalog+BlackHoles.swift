import Foundation

extension TAPClient {
    /// ESA's Gaia archive, for Gaia DR3's binary-star orbit solutions.
    static let gaia = TAPClient(syncURL: URL(string: "https://gea.esac.esa.int/tap-server/tap/sync")!)
}

/// Black holes:
///
/// | Data | Source |
/// |---|---|
/// | Sagittarius A*'s position | SIMBAD |
/// | Sagittarius A*'s distance and mass, M87*'s image mass | Papers, in `BlackHoleReferences` |
/// | Stellar black holes in X-ray transients | BlackCAT (Corral-Santana et al. 2016) via VizieR |
/// | Gaia BH1 and BH2 distances | Gaia DR3 two-body orbit solutions (ESA Gaia archive) |
/// | Cygnus X-1's distance | Gaia EDR3 parallax via SIMBAD |
/// | Galaxy black-hole masses | van den Bosch (2016) via VizieR, matched to Cosmicflows-4 |
extension CosmicCatalog: BlackHoleRepo {
    private static let blackHoleAge: TimeInterval = 180 * 86400

    func milkyWayBlackHoles() async throws -> [BlackHole] {
        try await cached(DiskCache<[BlackHole]>(name: "black-holes-milky-way-v1"), maxAge: Self.blackHoleAge) {
            async let sgrATask = self.sagittariusAStar()
            async let transientsTask = self.blackCAT()
            async let gaiaTask = self.gaiaBlackHoles()
            async let cygnusTask = self.cygnusX1()
            let (sgrA, transients, gaia, cygnus) = try await (sgrATask, transientsTask, gaiaTask, cygnusTask)
            return try Self.nonEmpty("Black holes", [sgrA, cygnus].compactMap { $0 } + gaia + transients)
        }
    }

    /// Sagittarius A*: SIMBAD's position, with the GRAVITY distance and mass.
    private func sagittariusAStar() async throws -> BlackHole {
        let rows = try await TAPClient.simbad.query("""
            SELECT b.ra, b.dec FROM basic AS b JOIN ident AS i ON i.oidref = b.oid WHERE i.id = 'NAME Sgr A*'
            """)
        guard let row = rows.first, let ra = row.double("ra"), let dec = row.double("dec") else {
            throw CatalogError.unreadable("Sagittarius A*'s position")
        }
        let r0 = BlackHoleReferences.sgrADistance, m = BlackHoleReferences.sgrAMass, image = BlackHoleReferences.sgrAImageMass
        return BlackHole(
            id: "sgr-a-star", name: "Sagittarius A*", aliases: ["Sgr A*", "Galactic Centre", "Galactic Center"],
            kind: .supermassive, setting: .galacticCentre, raDeg: ra, decDeg: dec,
            distanceParsecs: r0.value, distanceErrorParsecs: r0.plus,
            distanceMethod: "From the orbits of stars around it (VLTI/GRAVITY)",
            masses: [
                .init(suns: m.value, plus: m.plus, minus: m.minus, method: "Orbits of stars around it", source: m.citation),
                .init(suns: image.value, plus: image.plus, minus: image.minus, method: "Size of its shadow in the Event Horizon Telescope image", source: image.citation),
            ],
            discoveryYear: 1974,
            sources: ["Position: SIMBAD", "Distance and mass: \(m.citation)", "Image mass: \(image.citation)",
                      "Discovered as a radio source by Balick & Brown 1974, ApJ 194, 265"],
            notes: ["Its distance is the Sun's distance from the Galactic Centre, measured by tracking stars on tight orbits around it for over 25 years."]
        )
    }

    /// Black holes in X-ray transients from BlackCAT: positions and distances (table A1) and, for
    /// the ones weighed from their companion's orbit, masses (table A4).
    private func blackCAT() async throws -> [BlackHole] {
        async let positionsTask = TAPClient.vizier.query("""
            SELECT Year, Name, f_Name, Ctp, RAJ2000, DEJ2000, l_Dist, Dist, e_Dist, u_Dist FROM "J/A+A/587/A61/tablea1"
            """)
        // E_M1 and e_M1 differ only by case, so they're quoted to tell them apart.
        async let dynamicsTask = TAPClient.vizier.query("""
            SELECT Name, Ctp, SpType, Porb, "f(M1)", "e_f(M1)", l_M1, M1, "E_M1", "e_M1", M1u, Ref FROM "J/A+A/587/A61/tablea4"
            """)
        let (positions, dynamics) = try await (positionsTask, dynamicsTask)
        var weighed: [String: TAPClient.Row] = [:]
        for row in dynamics { if let name = row["Name"] { weighed[name] = row } }

        let holes = positions.compactMap { row -> BlackHole? in
            guard let name = row["Name"], !name.isEmpty, let ra = row.double("RAJ2000"), let dec = row.double("DEJ2000") else { return nil }
            let d = weighed[name]
            var hole = BlackHole(
                id: "blackcat-\(name)", name: name,
                aliases: Self.counterparts(row["Ctp"]) + Self.counterparts(d?["Ctp"]),
                kind: .stellar, setting: .xRayTransient, raDeg: ra, decDeg: dec,
                discoveryYear: row.int("Year")
            )
            var seen = Set<String>()
            hole.aliases = hole.aliases.filter { seen.insert($0).inserted }
            if let kpc = row.double("Dist") {
                hole.distanceParsecs = kpc * 1000
                hole.distanceErrorParsecs = row.double("e_Dist").map { $0 * 1000 }
                var limit = BlackHole.Limit(flag: row["l_Dist"])
                // ":" marks an uncertain distance; one with no error given is only approximate too.
                if limit == .none, row["u_Dist"] == ":" || hole.distanceErrorParsecs == nil { limit = .approximate }
                hole.distanceLimit = limit
                hole.distanceMethod = "Published estimates compiled by BlackCAT"
            }
            if let d {
                if let m = d.double("M1") {
                    let top = d.double("M1u")
                    hole.masses = [.init(
                        suns: m, plus: d.double("E_M1"), minus: d.double("e_M1") ?? d.double("E_M1"),
                        rangeTop: top, limit: BlackHole.Limit(flag: d["l_M1"]),
                        method: "Its companion star's orbit and the tilt of that orbit",
                        source: Self.blackCATReferences(d["Ref"])
                    )]
                }
                if let f = d.double("f(M1)") {
                    hole.massFunction = .init(suns: f, plus: d.double("e_f(M1)"), minus: d.double("e_f(M1)"), limit: .atLeast,
                                              method: "Its companion star's orbital speed and period (the mass function)",
                                              source: "BlackCAT (Corral-Santana et al. 2016)")
                }
                hole.companionType = d["SpType"].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
                hole.orbitalPeriodDays = d.double("Porb").map { $0 / 24 }
            }
            // Table A1 stars the ones weighed dynamically; SWIFT J1357.2-0933 has a firm mass
            // function in table A4 without being starred, as its companion star isn't seen.
            hole.isConfirmed = row["f_Name"] == "*" || hole.massFunction != nil
            hole.sources = ["BlackCAT (Corral-Santana et al. 2016, A&A 587, A61) via VizieR"]
            if !hole.isConfirmed {
                hole.notes.append("A black hole candidate: its X-ray outbursts look like those of known black holes, but no one has weighed it yet.")
            }
            if hole.distanceParsecs == nil {
                hole.notes.append("Its distance hasn't been measured, so it isn't on the map.")
            }
            return hole
        }
        return try Self.nonEmpty("BlackCAT", holes)
    }

    /// "(N. Mon 1975=V616 Mon)" → ["V616 Mon"]: other names in BlackCAT's counterpart column,
    /// leaving out nova years, which no one searches for.
    private static func counterparts(_ text: String?) -> [String] {
        guard let text else { return [] }
        let inner = text.trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespaces))
        return inner.split(separator: "=").map { $0.split(separator: " ").joined(separator: " ") }
            .filter { !$0.isEmpty && !$0.hasPrefix("N.") }
    }

    /// "Cantrell2010;Orosz1994" → "Cantrell 2010; Orosz 1994".
    private static func blackCATReferences(_ text: String?) -> String {
        let refs = (text ?? "").split(separator: ";").map { ref -> String in
            let r = ref.trimmingCharacters(in: .whitespaces)
            guard let m = r.firstMatch(of: #/^(.*?)(\d{4})([a-z]?)$/#) else { return r }
            return "\(m.1) \(m.2)"
        }
        return refs.isEmpty ? "BlackCAT (Corral-Santana et al. 2016)" : "\(refs.joined(separator: "; ")), via BlackCAT"
    }

    /// Gaia BH1, BH2 and BH3. BH1 and BH2 are placed by the parallax of their Gaia DR3 orbit
    /// solutions: the single-star parallax in gaia_source ignores the orbit and is off (BH2's
    /// gives 1.49 kpc against the orbit's 1.16). BH3 has no DR3 orbit, so its distance is the
    /// discovery paper's.
    private func gaiaBlackHoles() async throws -> [BlackHole] {
        let ids = BlackHoleReferences.gaiaMasses.keys.sorted()
        let list = ids.map(String.init).joined(separator: ",")
        async let orbitsTask = TAPClient.gaia.query("""
            SELECT source_id, parallax, parallax_error FROM gaiadr3.nss_two_body_orbit WHERE source_id IN (\(list))
            """)
        async let sourcesTask = TAPClient.gaia.query("""
            SELECT source_id, ra, dec FROM gaiadr3.gaia_source WHERE source_id IN (\(list))
            """)
        let (orbits, sources) = try await (orbitsTask, sourcesTask)
        var parallaxes: [Int: (Double, Double)] = [:]
        for row in orbits {
            guard let id = row["source_id"].flatMap({ Int($0) }), let p = row.double("parallax"), let e = row.double("parallax_error"), p > 0 else { continue }
            parallaxes[id] = (p, e)
        }
        // Named in order of discovery: BH1 (2022), BH2 (2023), BH3 (2024).
        let names: [Int: (String, Int)] = [4373465352415301632: ("Gaia BH1", 2022), 5870569352746779008: ("Gaia BH2", 2023), 4318465066420528000: ("Gaia BH3", 2024)]
        return sources.compactMap { row -> BlackHole? in
            guard let id = row["source_id"].flatMap({ Int($0) }), let named = names[id], let mass = BlackHoleReferences.gaiaMasses[id],
                  let ra = row.double("ra"), let dec = row.double("dec")
            else { return nil }
            var hole = BlackHole(id: "gaia-\(id)", name: named.0, aliases: ["Gaia DR3 \(id)"], kind: .stellar, setting: .dormantBinary,
                                 raDeg: ra, decDeg: dec, discoveryYear: named.1)
            hole.masses = [.init(suns: mass.value, plus: mass.plus, minus: mass.minus,
                                 method: "Its companion star's orbit, from Gaia's measurements of its wobble and the star's radial velocities",
                                 source: mass.citation)]
            if let plx = parallaxes[id] {
                let (p, e) = plx
                hole.distanceParsecs = 1000 / p
                hole.distanceErrorParsecs = 1000 / p * e / p
                hole.distanceMethod = "Parallax from its Gaia DR3 orbit solution"
                hole.sources = ["Position and distance: Gaia DR3 (nss_two_body_orbit)", "Mass: \(mass.citation)"]
            } else {
                let d = BlackHoleReferences.gaiaBH3Distance
                hole.distanceParsecs = d.value
                hole.distanceErrorParsecs = d.plus
                hole.distanceMethod = "Parallax from its pre-release Gaia orbit, as published"
                hole.sources = ["Position: Gaia DR3", "Distance and mass: \(mass.citation)"]
                hole.notes.append("Gaia DR3 has no orbit for it yet, so its distance is the discovery paper's rather than a catalog's.")
            }
            hole.notes.append("Found only by the wobble of the star orbiting it: it isn't feeding, so it gives off no X-rays.")
            return hole
        }
    }

    /// Cygnus X-1, the first black hole widely accepted as one: a persistent X-ray source, so it
    /// isn't in BlackCAT. Placed by its companion HD 226868's Gaia EDR3 parallax from SIMBAD.
    private func cygnusX1() async throws -> BlackHole? {
        let rows = try await TAPClient.simbad.query("""
            SELECT b.ra, b.dec, b.plx_value, b.plx_err, b.sp_type FROM basic AS b JOIN ident AS i ON i.oidref = b.oid WHERE i.id = 'HD 226868'
            """)
        guard let row = rows.first, let ra = row.double("ra"), let dec = row.double("dec") else { return nil }
        let mass = BlackHoleReferences.cygX1Mass
        var hole = BlackHole(id: "cyg-x-1", name: "Cygnus X-1", aliases: ["Cyg X-1", "HD 226868", "V1357 Cyg"],
                             kind: .stellar, setting: .xRayPersistent, raDeg: ra, decDeg: dec, discoveryYear: 1964)
        if let p = row.double("plx_value"), let e = row.double("plx_err"), p > 0, e < 0.2 * p {
            hole.distanceParsecs = 1000 / p
            hole.distanceErrorParsecs = 1000 / p * e / p
            hole.distanceMethod = "Gaia parallax of its companion star"
        }
        hole.masses = [.init(suns: mass.value, plus: mass.plus, minus: mass.minus,
                             method: "Its companion star's orbit, with a radio parallax distance", source: mass.citation)]
        hole.companionType = row["sp_type"].flatMap { $0.isEmpty ? nil : $0 }
        hole.sources = ["Position and distance: SIMBAD (Gaia EDR3 parallax of HD 226868)", "Mass: \(mass.citation)"]
        hole.notes.append("Discovered in X-rays on a rocket flight in 1964; it orbits the blue supergiant HD 226868 every 5.6 days.")
        return hole
    }

    // MARK: Supermassive black holes

    func supermassiveBlackHoles() async throws -> [Int: BlackHole] {
        try await cached(DiskCache<[Int: BlackHole]>(name: "black-holes-supermassive-v1"), maxAge: Self.blackHoleAge) {
            // E_logBHMass and e_logBHMass differ only by case, so they're quoted to tell them apart.
            async let massesTask = TAPClient.vizier.query("""
                SELECT Name, Dist, e_Dist, logBHMass, "E_logBHMass", "e_logBHMass", Meth, Refs, "_RA", "_DE" \
                FROM "J/ApJ/831/134/table2" WHERE logBHMass > 0
                """)
            async let refsTask = TAPClient.vizier.query("""
                SELECT Ref, BibCode, Auth FROM "J/ApJ/831/134/refs"
                """)
            let (rows, refRows) = try await (massesTask, refsTask)
            var refs: [Int: String] = [:]
            for row in refRows {
                guard let n = row.int("Ref"), let auth = row["Auth"] else { continue }
                let year = row["BibCode"].map { String($0.prefix(4)) } ?? ""
                refs[n] = "\(auth) \(year)".trimmingCharacters(in: .whitespaces)
            }
            let entries = rows.compactMap { row -> (ra: Double, dec: Double, row: TAPClient.Row)? in
                guard let ra = row.double("_RA"), let dec = row.double("_DE") else { return nil }
                return (ra, dec, row)
            }
            let pgcs = try await Self.cosmicflowsMatches(entries.map { ($0.ra, $0.dec) })
            var holes: [Int: BlackHole] = [:]
            for (entry, pgc) in zip(entries, pgcs) {
                guard let pgc, let hole = Self.supermassive(entry.row, ra: entry.ra, dec: entry.dec, pgc: pgc, refs: refs) else { continue }
                holes[pgc] = hole
            }
            guard !holes.isEmpty else { throw CatalogError.unreadable("Galaxy black holes") }
            return holes
        }
    }

    /// The Cosmicflows-4 galaxy within 1′ of each position, by PGC number, in one query.
    private static func cosmicflowsMatches(_ positions: [(ra: Double, dec: Double)]) async throws -> [Int?] {
        let r = 1.0 / 60
        let boxes = positions.map { p in
            let dRA = r / max(cos(p.dec * .pi / 180), 0.01)
            return String(format: "(DEJ2000 BETWEEN %.5f AND %.5f AND RAJ2000 BETWEEN %.5f AND %.5f)", p.dec - r, p.dec + r, p.ra - dRA, p.ra + dRA)
        }
        let rows = try await TAPClient.vizier.query("""
            SELECT PGC, RAJ2000, DEJ2000 FROM "J/ApJ/944/94/table2" WHERE \(boxes.joined(separator: " OR "))
            """)
        let galaxies = rows.compactMap { row -> (pgc: Int, ra: Double, dec: Double)? in
            guard let id = row.int("PGC"), let ra = row.double("RAJ2000"), let dec = row.double("DEJ2000") else { return nil }
            return (id, ra, dec)
        }
        return positions.map { p in
            var best: (pgc: Int, separation: Double)?
            for g in galaxies {
                let dRA = (g.ra - p.ra) * cos(p.dec * .pi / 180), dDec = g.dec - p.dec
                let s = (dRA * dRA + dDec * dDec).squareRoot()
                if s < r, s < (best?.separation ?? .infinity) { best = (g.pgc, s) }
            }
            return best?.pgc
        }
    }

    /// One row of van den Bosch (2016) as a black hole. Masses are given as log₁₀ with errors
    /// above and below; a lower error as big as the value itself means only an upper limit.
    private static func supermassive(_ row: TAPClient.Row, ra: Double, dec: Double, pgc: Int, refs: [Int: String]) -> BlackHole? {
        guard let raw = row["Name"], let log = row.double("logBHMass") else { return nil }
        let plus = row.double("E_logBHMass") ?? 0, minus = row.double("e_logBHMass") ?? 0
        let method: String
        switch row["Meth"]?.trimmingCharacters(in: .whitespaces) ?? "" {
        case "gas", "CO": method = "Gas orbiting it (gas dynamics)"
        case "star", "stars": method = "Motions of the stars around it (stellar dynamics)"
        case "maser": method = "Water masers orbiting it"
        case "reverb": method = "Echoes of its flickering light (reverberation mapping)"
        default: method = "Dynamical"
        }
        let papers = (row["Refs"] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)).flatMap { refs[$0] } }
        let source = "van den Bosch 2016" + (papers.isEmpty ? "" : ", from \(papers.joined(separator: "; "))")
        let mass: BlackHole.Mass = minus >= log
            ? .init(suns: pow(10, log + plus), limit: .atMost, method: method, source: source)
            : .init(suns: pow(10, log), plus: pow(10, log + plus) - pow(10, log), minus: pow(10, log) - pow(10, log - minus),
                    method: method, source: source)
        let galaxy = prettyName(raw)
        let isM87 = raw == BlackHoleReferences.m87CatalogName
        var hole = BlackHole(id: "smbh-\(pgc)", name: isM87 ? "M87*" : "\(galaxy)'s black hole", aliases: isM87 ? ["M87*", "M 87", galaxy] : [galaxy],
                             kind: .supermassive, setting: .galaxyCentre, raDeg: ra, decDeg: dec, hostPGC: pgc)
        if let mpc = row.double("Dist") {
            hole.distanceParsecs = mpc * 1e6
            hole.distanceErrorParsecs = row.double("e_Dist").map { $0 * 1e6 }
            hole.distanceMethod = "The distance its mass was worked out for"
        }
        hole.masses = [mass]
        hole.sources = ["Mass: van den Bosch 2016, ApJ 831, 134, via VizieR", "Galaxy: matched to Cosmicflows-4 by position"]
        if isM87 {
            let image = BlackHoleReferences.m87ImageMass
            hole.masses.insert(.init(suns: image.value, plus: image.plus, minus: image.minus,
                                     method: "Size of its shadow in the Event Horizon Telescope image", source: image.citation), at: 0)
            hole.sources.append("Image mass: \(image.citation)")
            hole.discoveryYear = 2019
            hole.notes.append("The first black hole ever imaged (2019). The image and the gas around it give different masses; both are published, so both are shown.")
        }
        if row["Meth"]?.contains("reverb") == true {
            hole.notes.append("Reverberation masses rest on an average scale factor for how gas moves near black holes, so they're less certain than the error suggests.")
        }
        return hole
    }

    /// "NGC4486" → "NGC 4486", "IC0342" → "IC 342"; other names as given.
    private static func prettyName(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let m = n.firstMatch(of: #/^(NGC|IC|UGC|ESO|Mrk|PGC)0*(\d.*)$/#) else { return n }
        return "\(m.1) \(m.2)"
    }
}
