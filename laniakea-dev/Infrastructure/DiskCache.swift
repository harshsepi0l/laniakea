import Foundation

/// Keeps the last good API result as JSON in the Caches directory, so data still shows offline.
struct DiskCache<Value: Codable> {
    let name: String

    private var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name).json")
    }

    /// The cached value, or nil if there is none or it is older than `maxAge`.
    func load(maxAge: TimeInterval? = nil) -> Value? {
        if let maxAge {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date().timeIntervalSince(modified) < maxAge
            else { return nil }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
