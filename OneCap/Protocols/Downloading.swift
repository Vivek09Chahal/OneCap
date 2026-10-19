import Foundation

protocol Downloading: Sendable {
    func data(_ url: URL) async throws -> Data
}
