import Foundation
import Observation

struct PluginToolRequest: Identifiable, Sendable {
    let id = UUID()
    let plugin: String
    let tool: String
    let arguments: String
}

@MainActor @Observable final class PluginToolApprover {
    private(set) var request: PluginToolRequest?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?

    func approve(plugin: String, tool: String, arguments: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        let pending = PluginToolRequest(plugin: plugin, tool: tool, arguments: arguments)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                resolve(false)
                self.continuation = continuation
                request = pending
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.request?.id == pending.id { self?.resolve(false) }
            }
        }
    }

    func resolve(_ allowed: Bool) {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(returning: allowed)
    }
}

struct ProviderPluginContext: Sendable {
    var servers: [PluginServer] = []
    var transport: PluginMCPClient.Transport? = nil
    var approve: @Sendable (String, String, String) async -> Bool = { _, _, _ in false }
}

actor ProviderPlugins {
    private struct Route {
        let server: PluginServer
        let client: PluginMCPClient
        let tool: PluginTool
        let alias: String
    }
    private var routes: [Route] = []
    private var clients: [PluginMCPClient] = []
    private let context: ProviderPluginContext
    init(context: ProviderPluginContext) { self.context = context }

    func prepare() async throws -> [PluginJSON] {
        for (serverIndex, server) in context.servers.enumerated() {
            let client = try PluginMCPClient(endpoint: server.connection.endpoint, token: server.token, transport: context.transport)
            clients.append(client)
            let tools = try await client.tools()
            for (toolIndex, tool) in tools.enumerated() {
                routes.append(Route(server: server, client: client, tool: tool, alias: "plugin_\(serverIndex)_\(toolIndex)"))
            }
            guard routes.count <= 126 else { throw AppFailure("Enabled plugins expose too many tools. Disable some plugins or narrow their server tool sets.") }
        }
        return routes.map { route in
            .object(["type": .string("function"), "function": .object([
                "name": .string(route.alias),
                "description": .string("\(route.server.connection.name): \(route.tool.name). \(route.tool.description)"),
                "parameters": route.tool.schema])])
        }
    }

    func execute(name: String, arguments: String) async throws -> String {
        guard let route = routes.first(where: { $0.alias == name }) else { throw AppFailure("Unknown plugin tool.") }
        guard await context.approve(route.server.connection.name, route.tool.name, arguments) else {
            try Task.checkCancellation()
            return "The user declined this plugin action. Do not retry it."
        }
        try Task.checkCancellation()
        return try await route.client.call(route.tool.name, arguments: arguments)
    }
    func close() async {
        for client in clients { await client.close() }
        clients = []; routes = []
    }
}
