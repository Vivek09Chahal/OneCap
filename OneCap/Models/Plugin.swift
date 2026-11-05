import Foundation

struct PluginDefinition: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let category: String
    let summary: String
    let setup: String
    let website: URL
    let endpoint: String?
    let iconURL: URL?
    var accountProvider: String? = nil
}

enum PluginCatalog {
    static let source = URL(string: "https://www.kimi.ai/help/plugins-and-skills/overview")!
    static let plugins: [PluginDefinition] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "PluginCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let plugins = try? JSONDecoder().decode([PluginDefinition].self, from: data) else { return [] }
        return plugins
    }()
}

struct PluginConnection: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var pluginID: String
    var name: String
    var endpoint: String
    var project: URL?
    var enabled = true
    var toolCount: Int
    var verifiedAt: Date
    // Tokens are stored only in Keychain, under this connection's UUID.
    var hasCredential: Bool
    var managedConnectionID: String? = nil
    var managedServiceURL: String? = nil

    func applies(to workspace: URL?) -> Bool {
        guard enabled else { return false }
        guard let project else { return true }
        guard let workspace else { return false }
        let root = project.standardizedFileURL.path
        let path = workspace.standardizedFileURL.path
        return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    static func validatedEndpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)),
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else {
            throw AppFailure("Use an HTTPS MCP endpoint without credentials, a query, or a fragment. HTTP is allowed only on localhost. Store access tokens in the token field.")
        }
        return url
    }
}

struct PluginServer: Sendable, Equatable {
    let connection: PluginConnection
    let token: String?

    var acpConfiguration: [String: Any] {
        var headers: [[String: String]] = []
        if let token, !token.isEmpty { headers.append(["name": "Authorization", "value": "Bearer \(token)"]) }
        return ["type": "http", "name": "onecap_" + connection.id.uuidString.replacingOccurrences(of: "-", with: ""),
                "url": connection.endpoint, "headers": headers]
    }
}
