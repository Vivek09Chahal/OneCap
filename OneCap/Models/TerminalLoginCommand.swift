import Foundation

struct TerminalAuthDescriptor: Sendable {
    /// Only legacy metadata supplies a command; first-class methods reuse the configured program.
    let command: String?
    let arguments: [String]
    let environment: [String: String]
}

struct TerminalLoginCommand: Sendable {
    let agentName: String
    let label: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let directory: URL
    
    init(agent: InstalledAgent, method: AuthMethod, directory: URL) throws {
        guard let descriptor = method.terminal else {
            throw AppFailure("Missing terminal login configuration.")
        }
        var environment = agent.processEnvironment()
        environment.merge(descriptor.environment) { _, value in value }
        let localBin = URL(fileURLWithPath: agent.directory).appendingPathComponent("node_modules/.bin")
            .path
        environment["PATH"] = localBin + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        if environment["TERM"] == nil { environment["TERM"] = "xterm-256color" }
        let executable: String
        let arguments: [String]
        if let legacyCommand = descriptor.command {
            if legacyCommand.hasPrefix("/") {
                executable = legacyCommand
            } else if legacyCommand.contains("/") {
                executable = directory.appendingPathComponent(legacyCommand).standardizedFileURL.path
            } else {
                guard
                    let match = environment["PATH"]?.split(separator: ":").map({
                        URL(fileURLWithPath: String($0)).appendingPathComponent(legacyCommand).path
                    }).first(where: { FileManager.default.isExecutableFile(atPath: $0) })
                        else {
                    throw AppFailure(
                        "The login program ‘\(legacyCommand)’ is unavailable. Check this agent’s installation.")
                }
                executable = match
            }
            arguments = descriptor.arguments
        } else {
            executable = agent.executable
            arguments = agent.arguments + descriptor.arguments
        }
        guard FileManager.default.isExecutableFile(atPath: executable), !executable.contains("\0"),
              arguments.allSatisfy({ !$0.contains("\0") }),
              environment.allSatisfy({
                  !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.contains("\0")
                  && !$0.value.contains("\0")
              })
                else {
            throw AppFailure("Invalid terminal login command or environment.")
        }
        self.agentName = agent.name
        self.label = method.name
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
    }
}
