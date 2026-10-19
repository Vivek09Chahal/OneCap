import Foundation

protocol NodeRuntimeProviding: Sendable {
    func binary() async throws -> URL
}
