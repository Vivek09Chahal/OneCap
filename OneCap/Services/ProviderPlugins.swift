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
    var packages: [InstalledPluginPackage] = []
    var packageRegistry: PluginPackageRegistry? = nil
    var workspace: URL? = nil
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
    private var packageRoutes: [(package: InstalledPluginPackage, tool: PluginManifest.Feature, alias: String)] = []
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
        if let registry = context.packageRegistry {
            for package in context.packages where package.enabled {
                _ = try await registry.approved(package)
                for tool in package.manifest.tools {
                    packageRoutes.append((package, tool, "plugin_local_\(packageRoutes.count)"))
                }
            }
        }
        guard routes.count + packageRoutes.count <= 126 else { throw AppFailure("Enabled plugins expose too many tools. Disable some plugins.") }
        let remote = routes.map { route -> PluginJSON in
            .object(["type": .string("function"), "function": .object([
                "name": .string(route.alias),
                "description": .string("\(route.server.connection.name): \(route.tool.name). \(route.tool.description)"),
                "parameters": route.tool.schema])])
        }
        return remote + packageRoutes.map { route in
            .object(["type": .string("function"), "function": .object([
                "name": .string(route.alias),
                "description": .string("\(route.package.manifest.name): \(route.tool.title). \(route.tool.description)"),
                "parameters": route.tool.inputSchema])])
        }
    }

    func execute(name: String, arguments: String) async throws -> String {
        if let route = packageRoutes.first(where: { $0.alias == name }), let registry = context.packageRegistry {
            guard await context.approve(route.package.manifest.name, route.tool.title, arguments) else {
                try Task.checkCancellation()
                return "The user declined this plugin action. Do not retry it."
            }
            let input = try JSONDecoder().decode(PluginJSON.self, from: Data(arguments.utf8))
            return try await PluginPackageRuntime(registry: registry).execute(
                route.package, kind: "tools/call", name: route.tool.id, arguments: input, workspace: context.workspace)
        }
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
        clients = []; routes = []; packageRoutes = []
    }
}
