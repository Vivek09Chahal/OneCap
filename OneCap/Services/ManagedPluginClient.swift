import Foundation

/// The Composio project key and Google tokens never enter the desktop app.
struct ManagedPluginClient: Sendable {
    struct Link: Decodable, Sendable {
        let id: UUID
        let redirectURL: URL
    }
    private struct Catalog: Decodable { let plugins: [String] }
    private struct Status: Decodable { let status: String }
    static let credentialID = UUID(uuidString: "31F995CD-850D-46D7-B9D0-567A22D48BD0")!
    let baseURL: URL
    let token: String
    private let transport: PluginMCPClient.Transport?

    init(baseURL: String, token: String, transport: PluginMCPClient.Transport? = nil) throws {
        self.baseURL = try PluginConnection.validatedEndpoint(baseURL)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure("OneCap account connections need a device credential. Ask your administrator to finish connection service setup.")
        }
        self.token = token
        self.transport = transport
    }

    @MainActor static func configured() throws -> ManagedPluginClient {
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["ONECAP_INTEGRATION_URL"] ?? UserDefaults.standard.string(forKey: "managedIntegrationURL")
                ?? Bundle.main.object(forInfoDictionaryKey: "OneCapIntegrationURL") as? String, !base.isEmpty else {
            throw AppFailure("Account linking is not available yet. The OneCap connection service must be configured by the app administrator before you can sign in.")
        }
        let token: String
        if let provisioned = environment["ONECAP_INTEGRATION_TOKEN"], !provisioned.isEmpty {
            try Keychain.save(provisioned, for: credentialID)
            token = provisioned
        } else {
            do { token = try Keychain.read(credentialID) }
            catch { throw AppFailure("OneCap connection service is configured, but this device has no sign-in credential. Ask your administrator to provision it.") }
        }
        return try ManagedPluginClient(baseURL: base, token: token)
    }

    func supportedPlugins() async throws -> Set<String> {
        let data = try await request("GET", "v1/catalog")
        return Set(try JSONDecoder().decode(Catalog.self, from: data).plugins)
    }

    func connect(pluginID: String) async throws -> Link {
        let body = try JSONEncoder().encode(["pluginID": pluginID])
        let link = try JSONDecoder().decode(Link.self, from: await request("POST", "v1/connections", body: body))
        guard link.redirectURL.scheme == "https", link.redirectURL.host == "connect.composio.dev",
              link.redirectURL.user == nil, link.redirectURL.password == nil else {
            throw AppFailure("The connection service returned an invalid sign-in link.")
        }
        return link
    }

    func waitUntilConnected(_ id: UUID, attempts: Int = 150, interval: Duration = .seconds(2)) async throws {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            let data = try await request("GET", "v1/connections/\(id.uuidString.lowercased())")
            let status = try JSONDecoder().decode(Status.self, from: data).status
            switch status {
            case "ACTIVE": return
            case "INITIALIZING", "INITIATED", "PENDING": break
            default: throw AppFailure("Account sign-in was declined, expired, or disconnected. Try connecting again.")
            }
            try await Task.sleep(for: interval)
        }
        throw AppFailure("Account sign-in timed out. Try connecting again.")
    }

    func disconnect(_ id: UUID) async throws {
        _ = try await request("DELETE", "v1/connections/\(id.uuidString.lowercased())")
    }

    func endpoint(for id: UUID) -> String {
        baseURL.appendingPathComponent("v1/connections/\(id.uuidString.lowercased())/mcp").absoluteString
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 65
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result: (Data, URLResponse)
        if let transport { result = try await transport(request) }
        else {
            let session = URLSession(configuration: .ephemeral, delegate: ManagedPluginNoRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw AppFailure("Invalid connection service response.") }
        switch response.statusCode {
        case 200..<300: return result.0
        case 401, 403: throw AppFailure("Your connection service credential has expired or this account needs to be reconnected.")
        case 404 where method == "DELETE": return Data()
        case 409: throw AppFailure("Account linking for this app is not configured on the OneCap connection service yet.")
        default: throw AppFailure("The OneCap connection service is unavailable (HTTP \(response.statusCode)). Please retry.")
        }
    }
}

private final class ManagedPluginNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
