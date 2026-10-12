import Foundation

/// Planets from NASA JPL's Horizons API (no key needed): today's orbital elements for the motion,
/// and the physical data sheet at the top of each response for the facts. A day's result is cached,
/// and the last good result is used when the network is down.
class HorizonsPlanetAPIService: PlanetRepo {
    private static let endpoint = URL(string: "https://ssd.jpl.nasa.gov/api/horizons.api")!
    /// Horizons IDs for Mercury through Neptune.
    private static let bodyIDs = ["199", "299", "399", "499", "599", "699", "799", "899"]

    private let cache = DiskCache<[Planet]>(name: "horizons-planets-v2")

    func loadPlanets() async throws -> [Planet] {
        if let fresh = cache.load(maxAge: 12 * 3600) { return fresh }
        do {
            // Horizons turns away simultaneous requests (HTTP 503), so ask one body at a time.
            var planets: [Planet] = []
            for id in Self.bodyIDs {
                planets.append(try await fetchPlanet(id: id))
            }
            planets.sort { $0.orbit.semiMajorAxisAU < $1.orbit.semiMajorAxisAU }
            cache.save(planets)
            return planets
        } catch {
            if let stale = cache.load() { return stale }
            throw error
        }
    }

    /// The Sun's physical data sheet (Horizons body 10).
    func loadSun(attempt: Int = 1) async throws -> SunDetails {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "COMMAND", value: "'10'"),
            URLQueryItem(name: "OBJ_DATA", value: "'YES'"), URLQueryItem(name: "MAKE_EPHEM", value: "'NO'"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 503, attempt < 3 {
            try await Task.sleep(for: .seconds(attempt))
            return try await loadSun(attempt: attempt + 1)
        }
        guard status == 200 else { throw HorizonsError.badResponse }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.result, decoded.error == nil, let sun = HorizonsParser.sun(result: text) else {
            throw HorizonsError.unreadable
        }
        return sun
    }

    private struct Response: Decodable {
        let result: String?
        let error: String?
    }

    private func fetchPlanet(id: String, attempt: Int = 1) async throws -> Planet {
        let (data, response) = try await URLSession.shared.data(from: Self.requestURL(id: id))
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 503, attempt < 3 {
            try await Task.sleep(for: .seconds(attempt))
            return try await fetchPlanet(id: id, attempt: attempt + 1)
        }
        guard status == 200 else { throw HorizonsError.badResponse }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.result, decoded.error == nil,
              let planet = HorizonsParser.planet(id: id, result: text)
        else { throw HorizonsError.unreadable }
        return planet
    }

    private static func requestURL(id: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let params = [
            "format": "json",
            "COMMAND": id,
            "OBJ_DATA": "YES",
            "MAKE_EPHEM": "YES",
            "EPHEM_TYPE": "ELEMENTS",
            "CENTER": "500@10",          // the Sun
            "REF_PLANE": "ECLIPTIC",
            "OUT_UNITS": "AU-D",
            "CSV_FORMAT": "YES",
            "START_TIME": formatter.string(from: today),
            "STOP_TIME": formatter.string(from: today.addingTimeInterval(86400)),
            "STEP_SIZE": "1d",
        ]
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.key == "format" ? $0.value : "'\($0.value)'") }
        return components.url!
    }
}

enum HorizonsError: LocalizedError {
    case badResponse
    case unreadable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "NASA JPL's server didn't respond. Check your connection and try again."
        case .unreadable: return "Planet data from NASA JPL couldn't be read."
        }
    }
}

/// Reads the plain-text `result` that Horizons returns.
enum HorizonsParser {
    static func planet(id: String, result: String) -> Planet? {
        guard let name = firstMatch(#"Target body name:\s*(.+?)\s*\("#, in: result),
              let orbit = orbit(from: result)
        else { return nil }

        let facts = keyValues(inHeaderOf: result)
        func value(where matches: (String) -> Bool) -> (key: String, value: String)? {
            facts.first { matches($0.key.lowercased()) }
        }

        let mass = facts.lazy.compactMap { pair -> Double? in
            guard let exponent = firstMatch(#"^mass\s*x\s*10\^(\d+)"#, in: pair.key.lowercased()).flatMap(Double.init),
                  let mantissa = number(in: pair.value)
            else { return nil }
            return mantissa * pow(10, exponent)
        }.first
        let temperature = value { $0.contains("temp") && !$0.contains("effect") }
        let tilt = value { $0.contains("obliquity") }.flatMap { pair -> Double? in
            guard let n = number(in: pair.value) else { return nil }
            // Mercury's is given in arcminutes.
            return firstMatch(#"^([\d.]+)'"#, in: pair.value) != nil ? n / 60 : n
        }

        return Planet(
            id: id,
            name: name,
            orbit: orbit,
            meanRadiusKm: value { $0.contains("mean radius") }.flatMap { number(in: $0.value) },
            massKg: mass,
            densityGramsPerCm3: value { $0.hasPrefix("density") }.flatMap { number(in: $0.value) },
            surfaceGravity: value { $0.hasPrefix("equ. grav") || $0.hasPrefix("g_e") }.flatMap { number(in: $0.value) },
            rotationPeriodHours: value { $0.contains("rot. period") || $0.contains("sidereal day") }.flatMap(hours),
            temperatureK: temperature.flatMap { number(in: $0.value) },
            temperatureIsAtOneBar: temperature?.key.contains("1 bar") ?? false,
            axialTiltDeg: tilt
        )
    }

    static func sun(result: String) -> SunDetails? {
        let facts = keyValues(inHeaderOf: result)
        guard !facts.isEmpty else { return nil }
        func value(_ matches: (String) -> Bool) -> Double? {
            facts.first { matches($0.key.lowercased()) }.flatMap { number(in: $0.value) }
        }
        /// Values given as "Name, 10^24 unit".
        func scaled(_ name: String) -> Double? {
            facts.lazy.compactMap { pair -> Double? in
                let key = pair.key.lowercased()
                guard key.hasPrefix(name), let exponent = firstMatch(#"10\^(\d+)"#, in: key).flatMap(Double.init),
                      let mantissa = number(in: pair.value)
                else { return nil }
                return mantissa * pow(10, exponent)
            }.first
        }
        return SunDetails(
            radiusKm: value { $0.contains("mean radius") },
            massKg: scaled("mass"),
            densityGramsPerCm3: value { $0.contains("density") },
            surfaceGravity: value { $0.hasPrefix("surface gravity") },
            escapeSpeedKmS: value { $0.hasPrefix("escape speed") },
            effectiveTemperatureK: value { $0.hasPrefix("effective temp") },
            luminosityWatts: scaled("luminosity"),
            rotationDays: value { $0.contains("rot. per") },
            axialTiltDeg: value { $0.hasPrefix("obliquity") },
            speedNearbyStarsKmS: firstMatch(#"nearby stars[\s\S]*?speed:\s*([\d.]+)"#, in: result).flatMap(Double.init),
            speedCosmicBackgroundKmS: firstMatch(#"CBR[\s\S]*?speed:\s*([\d.]+)"#, in: result).flatMap(Double.init)
        )
    }

    /// The first row of the elements table, matched to its column names (EC, IN, OM, W, MA, N, A, PR...).
    private static func orbit(from result: String) -> OrbitalElements? {
        let lines = result.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "$$SOE"), start + 1 < lines.count,
              let header = lines[..<start].last(where: { $0.contains("JDTDB") })
        else { return nil }
        let names = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let cells = lines[start + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var row: [String: Double] = [:]
        for (name, cell) in zip(names, cells) { row[name] = Double(cell) }

        guard let jd = row["JDTDB"], let e = row["EC"], let i = row["IN"], let node = row["OM"], let w = row["W"],
              let ma = row["MA"], let n = row["N"], let a = row["A"], let period = row["PR"]
        else { return nil }
        return OrbitalElements(epochJulianDay: jd, eccentricity: e, semiMajorAxisAU: a, inclinationDeg: i,
                               ascendingNodeDeg: node, argumentOfPerihelionDeg: w, meanAnomalyDeg: ma,
                               meanMotionDegPerDay: n, periodDays: period)
    }

    /// "Key = value" pairs from the data sheet between the first two rows of asterisks. Lines hold one
    /// or two columns; a column's value ends where two or more spaces lead into the next key.
    private static func keyValues(inHeaderOf result: String) -> [(key: String, value: String)] {
        let lines = result.components(separatedBy: .newlines)
        let rules = lines.indices.filter { lines[$0].count > 40 && lines[$0].allSatisfy { $0 == "*" } }
        guard rules.count > 1 else { return [] }
        var pairs: [(key: String, value: String)] = []
        for line in lines[(rules[0] + 1)..<rules[1]] {
            let parts = line.components(separatedBy: "=")
            guard parts.count > 1 else { continue }
            var key = parts[0].trimmingCharacters(in: .whitespaces)
            for (index, part) in parts.enumerated().dropFirst() {
                var segment = part.trimmingCharacters(in: .whitespaces)
                var nextKey = ""
                if index < parts.count - 1 {
                    // Split "value   Next key" at the last wide gap, or else before the first capitalized word.
                    if let gap = segment.range(of: #"\s{2,}"#, options: [.regularExpression, .backwards])
                        ?? segment.range(of: #"\s(?=[A-Z])"#, options: .regularExpression) {
                        nextKey = String(segment[gap.upperBound...])
                        segment = String(segment[..<gap.lowerBound])
                    }
                }
                pairs.append((key, segment))
                key = nextKey
            }
        }
        return pairs
    }

    /// Durations like "58.6463 d", "24.622962 hr", "17.24+-0.01 h" or "9h 55m 29.711 s", in hours.
    private static func hours(_ pair: (key: String, value: String)) -> Double? {
        let v = pair.value
        if let h = firstMatch(#"(\d+)h\s*\d+m"#, in: v).flatMap(Double.init),
           let m = firstMatch(#"\d+h\s*(\d+)m"#, in: v).flatMap(Double.init) {
            let s = firstMatch(#"\d+m\s*([\d.]+)\s*s"#, in: v).flatMap(Double.init) ?? 0
            return h + m / 60 + s / 3600
        }
        guard let n = number(in: v) else { return nil }
        let unit = firstMatch(#"^[~<\s]*[\d.]+(?:\s*\+-\s*[\d.]+)?\s*([a-zA-Z]*)"#, in: v) ?? ""
        switch unit {
        case "d": return n * 24
        case "h", "hr", "hrs": return n
        case "" where pair.key.lowercased().contains("hr"): return n
        default: return nil
        }
    }

    private static func number(in text: String) -> Double? {
        firstMatch(#"(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"#, in: text).flatMap(Double.init)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
