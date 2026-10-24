import Foundation

struct Registry: Codable, Sendable {
    let version: String
    let agents: [Agent]
}

struct Agent: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let version: String
    let description: String
    let repository: String?
    let website: String?
    let license: String?
    let distribution: Distribution
    var icon: String? = nil

    var iconURL: URL? {
        guard let icon, let url = URL(string: icon), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    
    var binary: BinaryDistribution? { distribution.binary?[Self.platform] }
    static var platform: String {
#if arch(arm64)
        "darwin-aarch64"
#else
        "darwin-x86_64"
#endif
    }
    var installKind: String {
        if binary != nil { return "macOS binary" }
        if distribution.npx != nil { return "Managed Node.js" }
        if distribution.uvx != nil { return "Python · coming soon" }
        return "Unavailable on this Mac"
    }
    var setupNote: String? {
        if id == "amp-acp" { return "Adapter only · Amp CLI is also required" }
        return nil
    }
    var canInstall: Bool { AgentCompatibility.installationIssue(for: self) == nil }
}

struct Distribution: Codable, Sendable, Equatable {
    let binary: [String: BinaryDistribution]?
    let npx: PackageDistribution?
    let uvx: PackageDistribution?
}
struct BinaryDistribution: Codable, Sendable, Equatable {
    let archive: String
    let cmd: String
    let args: [String]?
    let env: [String: String]?
    let sha256: String?
}
struct PackageDistribution: Codable, Sendable, Equatable {
    let package: String
    let args: [String]?
    let env: [String: String]?
}
struct InstalledAgent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let directory: String

    /// Agent configuration overrides inherited variables for every CLI invocation.
    func processEnvironment(
        inheriting inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        inherited.merging(environment) { _, configured in configured }
    }
}
struct Provider: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
}
struct AppFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
