import Foundation
import Testing
@testable import OneCapCore

private actor ManagedConnectionMock {
    var polls = 0
    var requests: [URLRequest] = []
    var status = "ACTIVE"
    var httpStatus = 200
    var redirect = "https://connect.composio.dev/link/test"
    let identifier = UUID()

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-secret")
        let value: PluginJSON
        if request.url!.path.hasSuffix("catalog") {
            value = .object(["plugins": .array([.string("gmail"), .string("google-calendar"), .string("figma"), .string("notion")])])
        } else if request.httpMethod == "POST" {
            let body = try JSONDecoder().decode(PluginJSON.self, from: request.httpBody!)
            #expect(body["pluginID"]?.string != nil)
            value = .object(["id": .string(identifier.uuidString), "redirectURL": .string(redirect)])
        } else {
            polls += 1
            value = .object(["status": .string(status)])
        }
        return (try JSONEncoder().encode(value), HTTPURLResponse(url: request.url!, statusCode: httpStatus,
                                                                httpVersion: nil, headerFields: nil)!)
    }
    func setStatus(_ value: String) { status = value }
    func setHTTPStatus(_ value: Int) { httpStatus = value }
    func setRedirect(_ value: String) { redirect = value }
}

@Test func managedPluginsIncludeCalendarFigmaAndOtherApps() async throws {
    let mock = ManagedConnectionMock()
    let client = try ManagedPluginClient(baseURL: "https://connections.example.com", token: "device-secret", transport: { try await mock.respond($0) })
    #expect(try await client.supportedPlugins() == ["gmail", "google-calendar", "figma", "notion"])
    for plugin in ["gmail", "google-calendar", "figma", "notion"] {
        let link = try await client.connect(pluginID: plugin)
        try await client.waitUntilConnected(link.id, attempts: 1, interval: .zero)
        #expect(client.endpoint(for: link.id).hasSuffix("/\(link.id.uuidString.lowercased())/mcp"))
        try await client.disconnect(link.id)
    }
    for plugin in ["gmail", "google-calendar", "figma", "github", "notion"] {
        #expect(PluginCatalog.plugins.first { $0.id == plugin }?.accountProvider != nil)
    }
}

@Test func managedConnectionsRejectUnsafeLinksAndSanitizeErrors() async throws {
    let mock = ManagedConnectionMock()
    let client = try ManagedPluginClient(baseURL: "https://connections.example.com", token: "device-secret", transport: { try await mock.respond($0) })
    for redirect in ["http://connect.composio.dev/link/test", "https://attacker.example/link/test", "https://secret@connect.composio.dev/link/test"] {
        await mock.setRedirect(redirect)
        await #expect(throws: AppFailure.self) { try await client.connect(pluginID: "figma") }
    }
    for status in [401, 403, 409, 500, 302] {
        await mock.setHTTPStatus(status)
        do { _ = try await client.supportedPlugins(); Issue.record("Expected error") }
        catch { #expect(!error.localizedDescription.contains("device-secret")) }
    }
    #expect(throws: AppFailure.self) { try ManagedPluginClient(baseURL: "http://remote.example", token: "secret") }
    #expect(throws: AppFailure.self) { try ManagedPluginClient(baseURL: "https://connections.example.com", token: "") }
}

@Test func managedConnectionDeclineTimeoutAndCancellation() async throws {
    let mock = ManagedConnectionMock()
    let client = try ManagedPluginClient(baseURL: "https://connections.example.com", token: "device-secret", transport: { try await mock.respond($0) })
    for status in ["FAILED", "EXPIRED", "DISABLED", "REVOKED", "INITIATED"] {
        await mock.setStatus(status)
        await #expect(throws: AppFailure.self) { try await client.waitUntilConnected(UUID(), attempts: 1, interval: .zero) }
    }
    await mock.setStatus("INITIATED")
    let task = Task { try await client.waitUntilConnected(UUID(), interval: .seconds(30)) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func managedConnectionMetadataRemainsBackwardCompatible() throws {
    let original = PluginConnection(pluginID: "custom", name: "Existing MCP", endpoint: "https://example.com/mcp",
                                    toolCount: 1, verifiedAt: Date(), hasCredential: false)
    let value = try JSONDecoder().decode(PluginJSON.self, from: JSONEncoder().encode(original))
    guard case .object(var json) = value else { Issue.record("Expected object"); return }
    json.removeValue(forKey: "managedConnectionID")
    json.removeValue(forKey: "managedServiceURL")
    let decoded = try JSONDecoder().decode(PluginConnection.self, from: JSONEncoder().encode(PluginJSON.object(json)))
    #expect(decoded == original)
    #expect(decoded.managedConnectionID == nil)
}
