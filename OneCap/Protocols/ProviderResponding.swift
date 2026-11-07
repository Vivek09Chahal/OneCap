import Foundation

protocol ProviderResponding: Sendable {
    func reply(provider: Provider, key: String, messages: [ChatMessage]) async throws -> String
    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?) async throws -> String
}

extension ProviderResponding {
    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?) async throws -> String {
        try await reply(provider: provider, key: key, messages: messages)
    }
}
