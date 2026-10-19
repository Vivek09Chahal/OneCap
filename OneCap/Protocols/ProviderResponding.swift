import Foundation

protocol ProviderResponding: Sendable {
    func reply(provider: Provider, key: String, messages: [ChatMessage]) async throws -> String
}
