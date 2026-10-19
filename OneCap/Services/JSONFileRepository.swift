import Foundation

/// One implementation for actor-isolated, atomic JSON snapshots. Invalid files
/// propagate an error; only a missing file returns the configured empty value.
actor JSONFileRepository<Value: Codable & Sendable>: SnapshotRepository {
    private let url: URL
    private let emptyValue: Value

    init(url: URL, emptyValue: Value) {
        self.url = url
        self.emptyValue = emptyValue
    }

    init(url: URL) where Value: RangeReplaceableCollection {
        self.url = url
        self.emptyValue = Value()
    }

    func load() throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return emptyValue }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
