import Foundation

enum AgentDistributionKind: String, CaseIterable, Identifiable, Sendable {
    case binary = "Binary"
    case cli = "CLI"
    var id: Self { self }
    
    var summary: String {
        switch self {
        case .binary: "Native agent executables, downloaded and managed inside OneCap."
        case .cli: "CLI agents installed with a runtime managed by OneCap."
        }
    }
}

/// Client compatibility, not an assertion about an account's subscription or quotas.
enum AgentCompatibility {
    static func unavailableReason(for id: String) -> String? {
        switch id {
        case "gemini":
            "Gemini CLI's individual Google sign-in can be rejected by Google. This integration is unavailable in OneCap for now. Choose another agent."
        case "amp-acp":
            "The Amp adapter requires a separate Amp CLI installation, which OneCap does not manage yet."
        default: nil
        }
    }
    
    static func installationIssue(for agent: Agent) -> String? {
        if let reason = unavailableReason(for: agent.id) { return reason }
        if let binary = agent.binary {
            guard let url = URL(string: binary.archive), url.scheme == "https", url.host != nil else {
                return "A supported HTTPS binary download is required."
            }
            guard let hash = binary.verifiedSHA256, hash.count == 64, hash.allSatisfy(\.isHexDigit) else {
                return "This binary does not provide a valid registry checksum."
            }
            guard binary.cmd != "node", !binary.cmd.hasPrefix("/"),
                  !binary.cmd.split(separator: "/").contains(".."), !binary.cmd.isEmpty
                    else { return "This binary requires a launch configuration OneCap does not support yet." }
            return nil
        }
        if let package = agent.distribution.npx?.package {
            guard !package.isEmpty, !package.hasPrefix("-"), !package.contains("://"),
                  !package.contains("..")
                    else {
                return "This npm distribution is not supported."
            }
            return nil
        }
        return "This agent has no supported distribution for this Mac."
    }
}

extension Agent {
    var distributionKind: AgentDistributionKind {
        if binary != nil { return .binary }
        if distribution.npx != nil || distribution.uvx != nil { return .cli }
        return .binary
    }
}

extension InstalledAgent {
    var distributionKind: AgentDistributionKind {
        let command = URL(fileURLWithPath: executable).lastPathComponent
        return command == "node" || command == "node.exe"
        || arguments.first?.contains("/node_modules/") == true ? .cli : .binary
    }
}
