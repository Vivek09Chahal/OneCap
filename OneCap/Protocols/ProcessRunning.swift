import Foundation

protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]?)
        async throws -> String
}

extension ProcessRunning {
    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await run(executable, arguments, environment: nil)
    }
}
