import Foundation

/// Persist an entire typed snapshot without exposing its storage mechanism.
protocol SnapshotRepository<Value>: Sendable {
    associatedtype Value: Codable & Sendable
    func load() async throws -> Value
    func save(_ value: Value) async throws
}
