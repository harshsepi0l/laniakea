import Foundation

/// Runs ADQL queries against IVOA TAP services (VizieR, SIMBAD, the NASA Exoplanet Archive) and
/// returns rows keyed by column name. All three speak the same protocol, so one client serves them.
struct TAPClient {
    let syncURL: URL
    /// The Exoplanet Archive spells the parameters in lower case and doesn't take REQUEST/LANG.
    var minimalParameters = false

    static let vizier = TAPClient(syncURL: URL(string: "https://tapvizier.cds.unistra.fr/TAPVizieR/tap/sync")!)
    static let simbad = TAPClient(syncURL: URL(string: "https://simbad.cds.unistra.fr/simbad/sim-tap/sync")!)
    static let exoplanetArchive = TAPClient(
        syncURL: URL(string: "https://exoplanetarchive.ipac.caltech.edu/TAP/sync")!,
        minimalParameters: true
    )

    typealias Row = [String: String]

    /// `timeout` is how long to wait for an answer. Lookups that only add extras (names, types)
    /// use a short one, so a slow service can't hold up a whole map.
    func query(_ adql: String, timeout: TimeInterval = 60) async throws -> [Row] {
        var request = URLRequest(url: syncURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = minimalParameters
            ? [("query", adql), ("format", "csv")]
            : [("REQUEST", "doQuery"), ("LANG", "ADQL"), ("FORMAT", "csv"), ("QUERY", adql)]
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        // URLComponents leaves "+" alone, which a form body would read as a space.
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { throw CatalogError.badResponse(syncURL.host ?? "") }
        // Errors come back as a VOTable even when CSV was requested.
        if text.hasPrefix("<?xml") { throw CatalogError.queryFailed(syncURL.host ?? "") }
        return Self.parseCSV(text)
    }

    /// RFC 4180 CSV: quoted fields may hold commas, newlines and doubled quotes.
    static func parseCSV(_ text: String) -> [Row] {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    let next = iterator.next()
                    if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": record.append(field); field = ""
            case "\n", "\r\n", "\r":
                record.append(field); field = ""
                records.append(record); record = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }

        guard let header = records.first else { return [] }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces) }
        return records.dropFirst().filter { $0.count == names.count }.map { values in
            Dictionary(uniqueKeysWithValues: zip(names, values.map { $0.trimmingCharacters(in: .whitespaces) }))
        }
    }
}

enum CatalogError: LocalizedError {
    case badResponse(String)
    case queryFailed(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let host): return "\(host) didn't respond. Check your connection and try again."
        case .queryFailed(let host): return "\(host) couldn't answer the request."
        case .unreadable(let what): return "\(what) couldn't be read."
        }
    }
}

extension TAPClient.Row {
    func double(_ key: String) -> Double? { self[key].flatMap { Double($0) } }
    func int(_ key: String) -> Int? {
        self[key].flatMap { Int($0) ?? Double($0).flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil } }
    }
}
