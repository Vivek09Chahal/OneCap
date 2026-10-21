import Foundation

enum OfficialCodex {
    static let version = "0.160.1"

    static func isCodex(_ id: String) -> Bool { id == "codex-acp" || id == "codex" }

    static func catalogAgent(replacing agent: Agent) -> Agent {
        Agent(
            id: agent.id, name: "Codex", version: version,
            description: "Official OpenAI Codex, connected directly through app-server",
            repository: "https://github.com/openai/codex",
            website: "https://developers.openai.com/codex/", license: "Apache-2.0",
            distribution: .init(binary: nil, npx: .init(
                package: "@openai/codex@\(version)", args: ["app-server"], env: nil), uvx: nil),
            icon: agent.icon)
    }

    /// Reuse the official executable shipped with an older adapter installation.
    /// Keep the agent ID so saved chats and the selected agent still resolve.
    static func directLaunch(_ agent: InstalledAgent) throws -> InstalledAgent {
        guard isCodex(agent.id) else { return agent }
        if agent.arguments.first?.contains("@agentclientprotocol/codex-acp/") == true {
            let directory = URL(fileURLWithPath: agent.directory)
            let package = directory.appendingPathComponent("node_modules/@openai/codex")
            let entry = package.appendingPathComponent("bin/codex.js")
            guard FileManager.default.fileExists(atPath: entry.path) else {
                throw AppFailure("Update Codex in Agent Harnesses to install the official OpenAI executable.")
            }
            let manifest = try JSONSerialization.jsonObject(
                with: Data(contentsOf: package.appendingPathComponent("package.json"))) as? [String: Any]
            guard manifest?["name"] as? String == "@openai/codex",
                  let version = manifest?["version"] as? String else {
                throw AppFailure("The official Codex installation could not be verified. Update Codex in Agent Harnesses.")
            }
            return InstalledAgent(
                id: agent.id, name: "Codex", version: version, executable: agent.executable,
                arguments: [entry.path, "app-server"], environment: agent.environment,
                directory: agent.directory)
        }
        guard !URL(fileURLWithPath: agent.executable).lastPathComponent.contains("codex-acp") else {
            throw AppFailure("Update Codex in Agent Harnesses to replace the ACP adapter with official Codex.")
        }
        return agent
    }
}
