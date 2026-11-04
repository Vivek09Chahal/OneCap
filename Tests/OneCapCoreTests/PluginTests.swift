import Foundation
import Testing
@testable import OneCapCore

@Test func pluginCatalogHasPublicKimiEntriesAndRequestedServices() throws {
    let catalog = PluginCatalog.plugins
    #expect(catalog.count >= 39)
    #expect(Set(catalog.map(\.id)).count == catalog.count)
    for id in ["gmail", "google-calendar", "figma", "wind", "sp-global", "gildata", "ifind", "sec", "world-bank", "imf", "stripe", "tianyancha", "notion", "baidu-netdisk", "github", "supabase", "neon", "cloudflare", "canva", "vivify", "dingtalk", "feishu", "wps", "huayu-yuandian"] {
        #expect(catalog.contains { $0.id == id })
    }
    for plugin in catalog {
        #expect(plugin.website.scheme == "https")
        #expect(!plugin.setup.isEmpty)
        if let endpoint = plugin.endpoint { _ = try PluginConnection.validatedEndpoint(endpoint) }
    }
}

@Test func pluginEndpointsAndScopeRejectCredentialLeaksAndSiblingProjects() throws {
    for url in ["http://example.com/mcp", "https://user:secret@example.com/mcp", "https://example.com/mcp?token=secret", "https://example.com/mcp#secret", "file:///tmp/mcp"] {
        #expect(throws: AppFailure.self) { try PluginConnection.validatedEndpoint(url) }
    }
    _ = try PluginConnection.validatedEndpoint("http://127.0.0.1:3845/mcp")
    var connection = PluginConnection(pluginID: "custom", name: "Scoped", endpoint: "https://example.com/mcp", project: URL(fileURLWithPath: "/projects/app"), toolCount: 1, verifiedAt: Date(), hasCredential: false)
    #expect(connection.applies(to: URL(fileURLWithPath: "/projects/app/src")))
    #expect(!connection.applies(to: URL(fileURLWithPath: "/projects/apple")))
    #expect(!connection.applies(to: nil))
    connection.enabled = false
    #expect(!connection.applies(to: URL(fileURLWithPath: "/projects/app")))
    connection.enabled = true; connection.project = nil
    #expect(connection.applies(to: nil))
    let config = PluginServer(connection: connection, token: "secret").acpConfiguration
    #expect(config["type"] as? String == "http")
    #expect((config["headers"] as? [[String: String]])?.first?["value"] == "Bearer secret")
    #expect(!String(decoding: try JSONEncoder().encode(connection), as: UTF8.self).contains("secret"))
}

private actor PluginMockServer {
    var methods: [String] = []
    var calls = 0
    let useSSE: Bool
    init(useSSE: Bool) { self.useSSE = useSSE }

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json, text/event-stream" || request.httpMethod == "DELETE")
        if request.httpMethod == "DELETE" {
            #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == "mock-session")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        }
        let data = try #require(request.httpBody)
        let json = try JSONDecoder().decode(PluginJSON.self, from: data)
        let method = try #require(json["method"]?.string)
        methods.append(method)
        var result: PluginJSON = .object([:])
        switch method {
        case "initialize":
            #expect(json["params"]?["capabilities"] == .object([:]))
            result = .object(["protocolVersion": .string("2025-06-18")])
        case "notifications/initialized":
            #expect(json["id"] == nil)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!)
        case "tools/list":
            #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == "mock-session")
            #expect(request.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18")
            if json["params"]?["cursor"]?.string == "page-2" {
                result = .object(["tools": .array([tool("second")])])
            } else {
                result = .object(["tools": .array([tool("first")]), "nextCursor": .string("page-2")])
            }
        case "tools/call":
            calls += 1
            #expect(json["params"]?["arguments"]?["query"]?.string == "hello")
            result = .object(["content": .array([.object(["type": .string("text"), "text": .string("found it")])])])
        default: Issue.record("Unexpected MCP method \(method)")
        }
        let response = PluginJSON.object(["jsonrpc": .string("2.0"), "id": json["id"] ?? .null, "result": result])
        let encoded = try JSONEncoder().encode(response)
        let body = useSSE ? Data(("event: message\ndata: " + String(decoding: encoded, as: UTF8.self) + "\n\n").utf8) : encoded
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                     headerFields: ["Content-Type": useSSE ? "text/event-stream" : "application/json", "Mcp-Session-Id": "mock-session"])!)
    }
    private func tool(_ name: String) -> PluginJSON {
        .object(["name": .string(name), "description": .string("Search"), "inputSchema": .object(["type": .string("object"), "properties": .object([:])])])
    }
}

@Test(arguments: [false, true]) func pluginMCPInitializesPaginatesCallsAndTerminatesSession(useSSE: Bool) async throws {
    let server = PluginMockServer(useSSE: useSSE)
    let client = try PluginMCPClient(endpoint: "https://example.com/mcp", token: "test-secret", transport: { try await server.respond($0) })
    let tools = try await client.tools()
    #expect(tools.map(\.name) == ["first", "second"])
    let result = try await client.call("first", arguments: #"{"query":"hello"}"#)
    #expect(result.contains("found it"))
    #expect(await server.calls == 1)
    #expect(await server.methods == ["initialize", "notifications/initialized", "tools/list", "tools/list", "tools/call"])
    await client.close()
}

@Test func pluginMCPSanitizesAuthorizationFailuresAndRejectsMismatchedResponses() async throws {
    for status in [200, 401, 403, 302] {
        let client = try PluginMCPClient(endpoint: "https://example.com/mcp", token: "private-token", transport: { request in
            let data = Data(#"{"jsonrpc":"2.0","id":999,"error":{"message":"private-token"}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        do { _ = try await client.tools(); Issue.record("Expected failure") }
        catch { #expect(!error.localizedDescription.contains("private-token")) }
        await client.close()
    }
}

@Test @MainActor func pluginApprovalsResolveAndCancelWithoutHanging() async throws {
    let approver = PluginToolApprover()
    let task = Task { await approver.approve(plugin: "Calendar", tool: "create", arguments: "{}") }
    while approver.request == nil { await Task.yield() }
    approver.resolve(true)
    #expect(await task.value)
    let cancelled = Task { await approver.approve(plugin: "Mail", tool: "send", arguments: "{}") }
    while approver.request == nil { await Task.yield() }
    cancelled.cancel()
    #expect(await cancelled.value == false)
    #expect(approver.request == nil)
}

@Test @MainActor func pluginConnectionsPersistAndShareBetweenWindows() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-plugin-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = directory.appendingPathComponent("state.json")
    let store = AppStore(stateURL: state)
    let window = store.makeWindowStore()
    let connection = PluginConnection(pluginID: "custom", name: "Mock", endpoint: "https://example.com/mcp", toolCount: 2, verifiedAt: Date(), hasCredential: false)
    try await store.savePlugin(connection, token: nil)
    #expect(window.plugins == [connection])
    let restored = AppStore(stateURL: state)
    try await restored.loadPlugins()
    #expect(restored.plugins.count == 1)
    #expect(try await restored.pluginServers(for: nil).count == 1)
    var disabled = connection; disabled.enabled = false
    try await window.savePlugin(disabled, token: nil)
    #expect(try await store.pluginServers(for: nil).isEmpty)
}
