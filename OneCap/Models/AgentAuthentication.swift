import Foundation

struct AuthMethod: Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let terminal: TerminalAuthDescriptor?
    var isAgentManaged: Bool { type == "agent" && terminal == nil }
    var isSupported: Bool { isAgentManaged || terminal != nil }
    
    init?(json: [String: Any], agent: InstalledAgent? = nil) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        type = json["type"] as? String ?? "agent"
        let legacy = (json["_meta"] as? [String: Any])?["terminal-auth"] as? [String: Any]
        // MiMo 0.1.16 advertises its inherited OpenCode login program, which is not installed.
        let isMiMoLogin = type != "terminal" && agent?.id == "mimocode" && id == "opencode-login"
            && legacy?["command"] as? String == "opencode"
        name = isMiMoLogin ? "Sign in to MiMo Code" : (json["name"] as? String ?? id)
        if type == "terminal" {
            guard let args = json["args"] as? [String],
                  json["command"] == nil
                    else { return nil }
            terminal = .init(
                command: nil, arguments: args, environment: json["env"] as? [String: String] ?? [:])
        } else if let legacy,
                  let command = legacy["command"] as? String
        {
            terminal = .init(
                command: isMiMoLogin ? agent?.executable : command,
                arguments: legacy["args"] as? [String] ?? [],
                environment: legacy["env"] as? [String: String] ?? [:])
        } else {
            terminal = nil
        }
    }
}

struct AgentConnectionKey: Hashable {
    let agentID: String
    let conversationID: UUID
    let folder: URL?
}
