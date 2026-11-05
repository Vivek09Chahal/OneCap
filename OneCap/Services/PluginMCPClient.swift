import Foundation

struct PluginTool: Sendable {
    let name: String
    let description: String
    let schema: PluginJSON
}

/// Streamable HTTP MCP. Credentials never follow redirects; tool calls are never retried.
actor PluginMCPClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let endpoint: URL
    private let token: String?
    private let transport: Transport?
    private let session: URLSession
    private var sessionID: String?
    private var protocolVersion = "2025-06-18"
    private var nextID = 0
    private var initialized = false
    private static let maximumBytes = 1024 * 1024

    init(endpoint: String, token: String?, transport: Transport? = nil) throws {
        self.endpoint = try PluginConnection.validatedEndpoint(endpoint)
        self.token = token
        self.transport = transport
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: PluginNoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func tools() async throws -> [PluginTool] {
        try await initialize()
        var tools: [PluginTool] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            let params: [String: PluginJSON] = cursor.map { ["cursor": .string($0)] } ?? [:]
            let result = try await request("tools/list", params)
            guard let page = result["tools"]?.array else { throw AppFailure("The MCP server returned an invalid tool list.") }
            for item in page {
                guard let name = item["name"]?.string, !name.isEmpty,
                      let schema = item["inputSchema"], schema["type"]?.string == "object",
                      !tools.contains(where: { $0.name == name }) else {
                    throw AppFailure("The MCP server returned an invalid or duplicate tool.")
                }
                tools.append(PluginTool(name: name, description: item["description"]?.string ?? name, schema: schema))
                guard tools.count <= 128 else { throw AppFailure("This connector exposes more than 128 tools. Configure a smaller tool set on the server.") }
            }
            cursor = result["nextCursor"]?.string
            if let cursor, !seen.insert(cursor).inserted { throw AppFailure("The MCP server repeated a page cursor.") }
            guard seen.count < 128 else { throw AppFailure("The MCP tool list exceeded the page limit.") }
        } while cursor != nil
        return tools
    }

    func call(_ name: String, arguments: String) async throws -> String {
        try await initialize()
        let args = try JSONDecoder().decode(PluginJSON.self, from: Data(arguments.utf8))
        guard case .object = args else { throw AppFailure("Plugin arguments must be a JSON object.") }
        let result = try await request("tools/call", ["name": .string(name), "arguments": args])
        // Preserve text, structured content and error status, including non-text content metadata.
        return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }

    func close() async {
        if let sessionID {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 5
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let transport { _ = try? await transport(request) }
            else { _ = try? await session.data(for: request) }
        }
        sessionID = nil
        initialized = false
        session.invalidateAndCancel()
    }

    private func initialize() async throws {
        guard !initialized else { return }
        let result = try await request("initialize", [
            "protocolVersion": .string(protocolVersion), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Edth"), "version": .string("0.1.0")])])
        guard let negotiated = result["protocolVersion"]?.string,
              ["2025-06-18", "2025-03-26"].contains(negotiated) else {
            throw AppFailure("This connector does not support a compatible Streamable HTTP MCP version.")
        }
        protocolVersion = negotiated
        _ = try await request("notifications/initialized", [:], notification: true)
        initialized = true
    }

    private func request(_ method: String, _ params: [String: PluginJSON], notification: Bool = false) async throws -> PluginJSON {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        var message: [String: PluginJSON] = ["jsonrpc": .string("2.0"), "method": .string(method), "params": .object(params)]
        if !notification { message["id"] = .number(Double(id)) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if method != "initialize" { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        request.httpBody = try JSONEncoder().encode(PluginJSON.object(message))
        let payload: PluginJSON
        if let transport {
            let (data, response) = try await transport(request)
            let http = try validate(response)
            if notification { return .null }
            guard data.count <= Self.maximumBytes else { throw AppFailure("Plugin response exceeds 1 MB.") }
            if http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
                payload = try Self.eventResponse(String(decoding: data, as: UTF8.self), id: id)
            } else { payload = try JSONDecoder().decode(PluginJSON.self, from: data) }
        } else {
            let (bytes, response) = try await session.bytes(for: request)
            let http = try validate(response)
            if notification { return .null }
            if http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
                var event = ""
                var count = 0
                var result: PluginJSON?
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    count += line.utf8.count
                    guard count <= Self.maximumBytes else { throw AppFailure("Plugin response exceeds 1 MB.") }
                    if line.isEmpty {
                        event = ""
                    } else if line.hasPrefix("data:") {
                        event += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) + "\n"
                        if let decoded = try? JSONDecoder().decode(PluginJSON.self, from: Data(event.utf8)) {
                            if decoded["id"] == .number(Double(id)) { result = decoded; break }
                            event = ""
                        }
                    }
                }
                guard let result else { throw AppFailure("The MCP event stream ended without a response.") }
                payload = result
            } else {
                var data = Data()
                for try await byte in bytes {
                    guard data.count < Self.maximumBytes else { throw AppFailure("Plugin response exceeds 1 MB.") }
                    data.append(byte)
                }
                payload = try JSONDecoder().decode(PluginJSON.self, from: data)
            }
        }
        guard payload["jsonrpc"]?.string == "2.0", payload["id"] == .number(Double(id)) else {
            throw AppFailure("The MCP server returned a mismatched response.")
        }
        if payload["error"] != nil {
            // Do not reflect server diagnostics, which may contain authorization headers.
            throw AppFailure("The MCP server rejected \(method). Check the connector's permissions and configuration.")
        }
        guard let result = payload["result"] else { throw AppFailure("The MCP server returned no result.") }
        return result
    }

    private func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw AppFailure("Invalid MCP HTTP response.") }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw AppFailure("Authorization is required. Reconnect this account in Plugins, or update the access token for a custom MCP connection.")
        case 404: throw AppFailure("MCP endpoint or session not found. Check the URL and reconnect.")
        default: throw AppFailure("MCP server returned HTTP \(http.statusCode).")
        }
        if let value = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = value }
        return http
    }

    static func eventResponse(_ text: String, id: Int) throws -> PluginJSON {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for event in normalized.components(separatedBy: "\n\n") {
            let data = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            if let value = try? JSONDecoder().decode(PluginJSON.self, from: Data(data.utf8)), value["id"] == .number(Double(id)) { return value }
        }
        throw AppFailure("The MCP event stream contains no matching response.")
    }
}

private final class PluginNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
