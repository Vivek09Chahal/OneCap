import Foundation

protocol ProviderResponding: Sendable {
    func reply(provider: Provider, key: String, messages: [ChatMessage]) async throws -> String
    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?) async throws -> String
    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?, plugins: ProviderPluginContext) async throws -> String
}

extension ProviderResponding {
    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?, plugins: ProviderPluginContext) async throws -> String {
        guard plugins.servers.isEmpty else { throw AppFailure("This provider adapter does not support plugin tools.") }
        return try await reply(provider: provider, key: key, messages: messages, workspace: workspace)
    }

    func reply(provider: Provider, key: String, messages: [ChatMessage], workspace: URL?) async throws -> String {
        try await reply(provider: provider, key: key, messages: messages)
    }
}
