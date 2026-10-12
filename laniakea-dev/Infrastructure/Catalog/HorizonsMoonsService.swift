import Foundation
import simd

/// Moons, dwarf planets and the Moon's sky position from NASA JPL's Horizons API. Horizons turns
/// away simultaneous requests (HTTP 503), so these go one at a time through `HorizonsGate` and retry
/// a 503 after a pause.
final class HorizonsMoonsService {
    private static let endpoint = URL(string: "https://ssd.jpl.nasa.gov/api/horizons.api")!
    private static let gravitationalConstant = 6.674_30e-11

    // MARK: Moons

    /// Every numbered moon in Horizons' list of major bodies, plus the named moons of Eris and
    /// Haumea, which Horizons files under their own numbers.
    func moonListings() async throws -> [MoonListing] {
        let text = try await request(["COMMAND": "MB"])
        var listings: [MoonListing] = []
        for line in text.components(separatedBy: .newlines) {
            // "      501  Io                                 JI" — ID, then the name in a fixed-width column.
            guard let id = HorizonsParser.firstMatch(#"^\s*(\d+)  "#, in: line),
                  let primary = Moon.primaryID(ofMoon: id),
                  var name = HorizonsParser.firstMatch(#"^\s*\d+  (.{1,34})"#, in: line)?.trimmingCharacters(in: .whitespaces)
            else { continue }
            if name.isEmpty {
                // Numbered but not yet named: "S2010_J1" in the designation column is S/2010 J 1.
                guard let year = HorizonsParser.firstMatch(#"^\s*\d+  .{34} S(\d{4})_"#, in: line),
                      let planet = HorizonsParser.firstMatch(#"^\s*\d+  .{34} S\d{4}_([A-Z])"#, in: line),
                      let number = HorizonsParser.firstMatch(#"^\s*\d+  .{34} S\d{4}_[A-Z](\d+)"#, in: line)
                else { continue }
                name = "S/\(year) \(planet) \(number)"
            }
            guard !name.contains("barycenter"), !name.contains("primary body") else { continue }
            listings.append(MoonListing(id: id, name: name, primaryID: primary))
        }
        guard !listings.isEmpty else { throw HorizonsError.unreadable }
        return listings
    }

    /// A moon's orbit around its primary today, with its physical data sheet, in one request.
    func moon(id: String) async throws -> Moon {
        guard let primary = Moon.primaryID(ofMoon: id) else { throw HorizonsError.unreadable }
        let centre = DwarfPlanets.moonCentre(of: primary) ?? primary
        let text = try await request(elementsParams(command: id, centre: centre))
        guard let orbit = HorizonsParser.orbit(from: text),
              let name = HorizonsParser.firstMatch(#"Target body name:\s*(.+?)\s*\("#, in: text)
        else { throw HorizonsError.unreadable }
        let facts = HorizonsParser.keyValues(inHeaderOf: text)
        func value(_ matches: (String) -> Bool) -> String? { facts.first { matches($0.key.lowercased()) }?.value }

        let radiusText = value { $0.contains("mean radius") }
            ?? value { $0.contains("radius") && !$0.contains("hill") && !$0.contains("gravity") }
            ?? value { $0 == "rad" }
        let radii = radiusText.flatMap(Self.radii)
        // A range ("9.56 - 29.7", Dysnomia) is too loose to give a mass.
        let gm = value { $0.hasPrefix("gm") && !$0.contains("sigma") && !$0.contains("rat") }
            .flatMap { $0.contains(" - ") ? nil : HorizonsParser.number(in: $0) }
        let mass = gm.map { $0 * 1e9 / Self.gravitationalConstant } ?? Self.mass(in: facts)
        return Moon(
            id: id, name: name, primaryID: primary, orbit: orbit,
            meanRadiusKm: radii?.mean, triaxialRadiiKm: radii?.axes,
            massKg: mass,
            densityGramsPerCm3: value { $0.contains("dens") }.flatMap(HorizonsParser.number(in:)),
            geometricAlbedo: value { $0.contains("albedo") }.flatMap(HorizonsParser.number(in:)),
            isSynchronous: value { $0.contains("rot") && $0.contains("period") }?.lowercased().contains("synchronous") ?? false
        )
    }

    // MARK: Dwarf planets

    func dwarfPlanets() async throws -> [DwarfPlanet] {
        var bodies: [DwarfPlanet] = []
        for body in DwarfPlanets.all {
            bodies.append(try await dwarfPlanet(body))
        }
        return bodies
    }

    private func dwarfPlanet(_ body: DwarfPlanets.Body) async throws -> DwarfPlanet {
        let text = try await request(elementsParams(command: body.orbitCommand, centre: "10"))
        // Pluto is a major body with a planet-style data sheet.
        if body.orbitCommand == "999" {
            guard let parsed = HorizonsParser.planet(id: body.id, result: text) else { throw HorizonsError.unreadable }
            // Pluto's sheet writes "Density (R=1195 km) = 1.86", which the planet parser splits at the
            // wrong "=", and calls gravity "Surface gravity"; both are read here instead.
            let facts = HorizonsParser.keyValues(inHeaderOf: text)
            let gravity = facts.first { $0.key.lowercased().hasPrefix("surface gravity") }.flatMap { Self.decimal(in: $0.value) }
            let density = HorizonsParser.firstMatch(#"Density \(R=\d+ km\)\s*=\s*([\d.]+)"#, in: text).flatMap(Double.init)
            let pluto = Planet(id: parsed.id, name: parsed.name, orbit: parsed.orbit, meanRadiusKm: parsed.meanRadiusKm,
                               massKg: parsed.massKg, densityGramsPerCm3: density, surfaceGravity: gravity ?? parsed.surfaceGravity,
                               rotationPeriodHours: parsed.rotationPeriodHours, temperatureK: nil, temperatureIsAtOneBar: false,
                               axialTiltDeg: parsed.axialTiltDeg)
            return DwarfPlanet(planet: pluto, designation: "134340", triaxialRadiiKm: nil, massIsEstimate: false,
                               geometricAlbedo: nil, absoluteMagnitude: nil, notes: ["Orbit and physical data: NASA JPL Horizons."])
        }
        guard let orbit = HorizonsParser.orbit(from: text) else { throw HorizonsError.unreadable }
        var sheet = Self.smallBodySheet(text)
        var notes = ["Orbit: NASA JPL Horizons, small-body record \(body.orbitCommand.dropLast())."]
        if let physical = body.physicalCommand {
            // The orbit record says "n.a." for size and mass; the TNO-satellite solution's primary
            // body record has them.
            let primary = Self.smallBodySheet(try await request(["COMMAND": physical, "OBJ_DATA": "YES", "MAKE_EPHEM": "NO"]))
            sheet = sheet.merged(with: primary)
            notes.append("Size and mass: Horizons record \(physical), from the orbits of its moons.")
        }
        if body.name == "Makemake", sheet.radii == nil {
            let axes = DwarfPlanets.makemakeRadiiKm
            sheet.radii = (cbrt(axes.reduce(1, *)), axes)
            notes.append("Size: Brown 2013 (ApJ Letters 767, L7), 1,434 × 1,422 km; Horizons has none. Its mass hasn't been measured.")
        }
        if body.name == "Eris" {
            // Horizons' 25.9 h comes from a light curve the asteroid lightcurve database flags as
            // possibly wrong; Eris turns once per orbit of Dysnomia (Szakáts et al. 2023, A&A 669, L3;
            // Bernstein et al. 2023, PSJ 4, 115).
            sheet.rotationHours = 15.786 * 24
            notes.append("Rotation: 15.79 days, locked to Dysnomia (Szakáts et al. 2023; Bernstein et al. 2023).")
        }
        let radius = sheet.radii?.mean
        let density: Double? = {
            guard let m = sheet.massKg, let r = radius else { return nil }
            return m * 1000 / (4.0 / 3 * .pi * pow(r * 1e5, 3))
        }()
        let gravity: Double? = {
            guard let gm = sheet.gm, let r = radius else { return nil }
            return gm * 1e9 / pow(r * 1000, 2)
        }()
        let name = HorizonsParser.firstMatch(#"Target body name:\s*\d*\s*(.+?)\s*\("#, in: text) ?? body.name
        let designation = HorizonsParser.firstMatch(#"Target body name:\s*\d*\s*.+?\s*\((.+?)\)"#, in: text)
        let number = String(body.orbitCommand.dropLast())
        let planet = Planet(id: body.id, name: name, orbit: orbit, meanRadiusKm: radius, massKg: sheet.massKg,
                            densityGramsPerCm3: density, surfaceGravity: gravity, rotationPeriodHours: sheet.rotationHours,
                            temperatureK: nil, temperatureIsAtOneBar: false, axialTiltDeg: nil)
        return DwarfPlanet(planet: planet, designation: designation.map { "\(number) · \($0)" } ?? number,
                           triaxialRadiiKm: sheet.radii?.axes, massIsEstimate: sheet.gmIsRange,
                           geometricAlbedo: sheet.albedo, absoluteMagnitude: sheet.h, notes: notes)
    }

    /// The "Asteroid physical parameters" block of a small-body record: `GM= …  RAD= …  ROTPER= …`.
    private struct SmallBodySheet {
        var gm: Double?
        var gmIsRange = false
        var radii: (mean: Double, axes: [Double]?)?
        var rotationHours: Double?
        var albedo: Double?
        var h: Double?

        var massKg: Double? { gm.map { $0 * 1e9 / HorizonsMoonsService.gravitationalConstant } }

        func merged(with other: SmallBodySheet) -> SmallBodySheet {
            var m = self
            if other.gm != nil { m.gm = other.gm; m.gmIsRange = other.gmIsRange }
            m.radii = other.radii ?? radii
            m.rotationHours = rotationHours ?? other.rotationHours
            m.albedo = other.albedo ?? albedo
            m.h = h ?? other.h
            return m
        }
    }

    private static func smallBodySheet(_ text: String) -> SmallBodySheet {
        let facts = HorizonsParser.keyValues(inHeaderOf: text)
        func value(_ key: String) -> String? {
            guard let raw = facts.first(where: { $0.key.uppercased() == key })?.value.trimmingCharacters(in: .whitespaces),
                  !raw.hasPrefix("n.a")
            else { return nil }
            return raw
        }
        var sheet = SmallBodySheet()
        if let gm = value("GM") {
            // Eris's is a range, "1069.1 - 1089.3 km^3/s^2": use its middle and mark the mass ≈.
            if let low = HorizonsParser.firstMatch(#"^([\d.]+)\s+-\s+[\d.]+"#, in: gm).flatMap(Double.init),
               let high = HorizonsParser.firstMatch(#"^[\d.]+\s+-\s+([\d.]+)"#, in: gm).flatMap(Double.init) {
                sheet.gm = (low + high) / 2
                sheet.gmIsRange = true
            } else {
                sheet.gm = HorizonsParser.number(in: gm)
            }
        }
        sheet.radii = value("RAD").flatMap(radii)
        sheet.rotationHours = value("ROTPER").flatMap(decimal)
        sheet.albedo = value("ALBEDO").flatMap(decimal)
        sheet.h = value("H").flatMap(decimal)
        return sheet
    }

    /// A number that may start at its decimal point, as small-body sheets write them (".090", "-.250").
    private static func decimal(in text: String) -> Double? {
        HorizonsParser.firstMatch(#"(-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)"#, in: text).flatMap(Double.init)
    }

    /// "1821.49", "734.5 +- 4.0", "13.1 x11.1 x9.3" or "1050 x 840 x 537 km". Three semi-axes give
    /// the volume-equivalent radius, the cube root of their product.
    private static func radii(_ text: String) -> (mean: Double, axes: [Double]?)? {
        if let a = HorizonsParser.firstMatch(#"^\s*([\d.]+)\s*x"#, in: text).flatMap(Double.init),
           let b = HorizonsParser.firstMatch(#"^\s*[\d.]+\s*x\s*([\d.]+)"#, in: text).flatMap(Double.init),
           let c = HorizonsParser.firstMatch(#"^\s*[\d.]+\s*x\s*[\d.]+\s*x\s*([\d.]+)"#, in: text).flatMap(Double.init) {
            return (cbrt(a * b * c), [a, b, c])
        }
        return HorizonsParser.number(in: text).map { ($0, nil) }
    }

    /// "Mass (10^20 kg ) = 1.08 (10^-4)" (Phobos: 1.08 × 10¹⁶ kg) or "Mass, x10^22 kg = 7.349".
    private static func mass(in facts: [(key: String, value: String)]) -> Double? {
        for pair in facts where pair.key.lowercased().hasPrefix("mass") {
            guard let exponent = HorizonsParser.firstMatch(#"10\^(-?\d+)"#, in: pair.key).flatMap(Double.init),
                  let mantissa = HorizonsParser.number(in: pair.value)
            else { continue }
            let extra = HorizonsParser.firstMatch(#"\(10\^(-?\d+)\)"#, in: pair.value).flatMap(Double.init) ?? 0
            return mantissa * pow(10, exponent + extra)
        }
        return nil
    }

    // MARK: The Moon in the sky

    /// The Moon's geocentric astrometric position every hour from an hour ago for two days. Only
    /// Earth's centre is sent to Horizons, never your location.
    func moonEphemeris(from start: Date = Date().addingTimeInterval(-3600), hours: Int = 48) async throws -> MoonEphemeris {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:00"
        let text = try await request([
            "COMMAND": "301", "OBJ_DATA": "NO", "MAKE_EPHEM": "YES", "EPHEM_TYPE": "VECTORS",
            "CENTER": "500@399", "REF_SYSTEM": "ICRF", "REF_PLANE": "FRAME", "OUT_UNITS": "KM-S",
            "VEC_TABLE": "1", "VEC_CORR": "LT", "CSV_FORMAT": "YES",
            "START_TIME": formatter.string(from: start),
            "STOP_TIME": formatter.string(from: start.addingTimeInterval(Double(hours) * 3600)),
            "STEP_SIZE": "1h",
        ])
        let lines = text.components(separatedBy: .newlines)
        guard let soe = lines.firstIndex(of: "$$SOE"), let eoe = lines.firstIndex(of: "$$EOE"), soe < eoe else {
            throw HorizonsError.unreadable
        }
        // Rows: JDTDB, calendar date, X, Y, Z.
        let samples: [MoonEphemeris.Sample] = lines[(soe + 1)..<eoe].compactMap { line in
            let cells = line.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard cells.count >= 5, let jd = cells[0], let x = cells[2], let y = cells[3], let z = cells[4] else { return nil }
            return MoonEphemeris.Sample(julianDayTDB: jd, x: x, y: y, z: z)
        }
        guard samples.count > 2 else { throw HorizonsError.unreadable }
        return MoonEphemeris(samples: samples)
    }

    // MARK: Requests

    private func elementsParams(command: String, centre: String) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        return [
            "COMMAND": command, "OBJ_DATA": "YES", "MAKE_EPHEM": "YES", "EPHEM_TYPE": "ELEMENTS",
            "CENTER": "500@\(centre)", "REF_PLANE": "ECLIPTIC", "OUT_UNITS": "AU-D", "CSV_FORMAT": "YES",
            "START_TIME": formatter.string(from: today),
            "STOP_TIME": formatter.string(from: today.addingTimeInterval(86400)),
            "STEP_SIZE": "1d",
        ]
    }

    private struct Response: Decodable {
        let result: String?
        let error: String?
    }

    private func request(_ params: [String: String]) async throws -> String {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
            + params.map { URLQueryItem(name: $0.key, value: "'\($0.value)'") }
        // URLComponents leaves ";" as is, and Horizons then rejects a small body's "136199;".
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: ";", with: "%3B")
        let url = components.url!
        return try await HorizonsGate.shared.run {
            for attempt in 1...4 {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode
                if status == 503, attempt < 4 {
                    try await Task.sleep(for: .seconds(attempt))
                    continue
                }
                guard status == 200 else { throw HorizonsError.badResponse }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                guard let text = decoded.result, decoded.error == nil else { throw HorizonsError.unreadable }
                return text
            }
            throw HorizonsError.badResponse
        }
    }
}

/// Lets one Horizons request run at a time.
actor HorizonsGate {
    static let shared = HorizonsGate()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy = true
        defer {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
        return try await work()
    }
}
