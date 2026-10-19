import Foundation

struct AuthMethod: Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let terminal: TerminalAuthDescriptor?
    var isAgentManaged: Bool { type == "agent" && terminal == nil }
    var isSupported: Bool { isAgentManaged || terminal != nil }
    
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        name = json["name"] as? String ?? id
        type = json["type"] as? String ?? "agent"
        if type == "terminal" {
            guard let args = json["args"] as? [String],
                  json["command"] == nil
                    else { return nil }
            terminal = .init(
                command: nil, arguments: args, environment: json["env"] as? [String: String] ?? [:])
        } else if let meta = json["_meta"] as? [String: Any],
                  let legacy = meta["terminal-auth"] as? [String: Any],
                  let command = legacy["command"] as? String
        {
            terminal = .init(
                command: command, arguments: legacy["args"] as? [String] ?? [],
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
