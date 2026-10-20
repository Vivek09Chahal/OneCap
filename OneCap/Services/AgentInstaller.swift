import Foundation

actor AgentInstaller: AgentInstalling {
    static let registryURL = URL(
        string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")!
    private let root: URL
    private let downloader: any Downloading
    private let runtime: NodeRuntime
    private var uninstallations: Set<String> = []
    private var installations: [String: Task<InstalledAgent, Error>] = [:]
    
    init(
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneCap"),
        downloader: any Downloading = HTTPDownloader()
    ) {
        self.root = root
        self.downloader = downloader
        self.runtime = NodeRuntime(root: root, downloader: downloader)
    }
    
    func catalog() async throws -> Registry {
        let data = try await downloader.data(Self.registryURL)
        let registry = try JSONDecoder().decode(Registry.self, from: data)
        return Registry(version: registry.version, agents: registry.agents.map { agent in
            // Keep the existing ID and chats while the registry still lists the retired CLI.
            guard agent.id == "kimi", agent.repository == "https://github.com/MoonshotAI/kimi-cli" else {
                return agent
            }
            let version = "2.2.0"
            // SHA-256 values from the official versioned kimi-code binary manifest.
            let platforms = [
                "darwin-aarch64": ("darwin-arm64", "dab42ead275f8a49e9ce30a6263f614fce5926455bed103d0d16940655619bf5"),
                "darwin-x86_64": ("darwin-x64", "894901e44ce5c7a2f610991698350ef20d1ffd4214b9dea902bbd16b12afddae"),
            ]
            let binaries = platforms.mapValues { target, checksum in
                BinaryDistribution(
                    archive: "https://code.kimi.com/kimi-code/binaries/\(version)/kimi-code-\(target)",
                    cmd: "./kimi", args: ["acp"], env: nil, sha256: checksum)
            }
            return Agent(
                id: agent.id, name: "Kimi Code CLI", version: version,
                description: "Moonshot AI’s Kimi Code coding agent",
                repository: "https://github.com/MoonshotAI/kimi-code",
                website: "https://moonshotai.github.io/kimi-code/", license: "MIT",
                distribution: .init(binary: binaries, npx: nil, uvx: nil), icon: agent.icon)
        })
    }
    
    func install(_ agent: Agent) async throws -> InstalledAgent {
        if let issue = AgentCompatibility.installationIssue(for: agent) { throw AppFailure(issue) }
        guard !uninstallations.contains(agent.id) else {
            throw AppFailure("This agent is being uninstalled.")
        }
        let key = "\(agent.id)@\(agent.version)"
        if let task = installations[key] { return try await task.value }
        let task = Task { try await installAgent(agent) }
        installations[key] = task
        defer { installations[key] = nil }
        return try await task.value
    }
    /// Remove only the managed per-agent directory, never paths supplied by saved metadata.
    /// Stage files first so a failed settings write can restore the installation.
    func uninstall(_ agent: InstalledAgent, repository: AppRepository) async throws
    -> AgentUninstallResult
    {
        let id = try PackageValidation.safeComponent(agent.id)
        guard !uninstallations.contains(id),
              !installations.keys.contains(where: { $0.hasPrefix("\(id)@") })
                else {
            throw AppFailure("Wait for this agent's installation or removal to finish.")
        }
        uninstallations.insert(id)
        defer { uninstallations.remove(id) }
        let directory = try PackageValidation.containedPath("agents/\(id)", in: root)
        let staged = try PackageValidation.containedPath(
            "agents/.uninstall-\(UUID().uuidString)", in: root)
        let hasFiles = FileManager.default.fileExists(atPath: directory.path)
        if hasFiles { try FileManager.default.moveItem(at: directory, to: staged) }
        let state: SavedAppState
        do {
            state = try await repository.unregisterAgent(id)
        } catch {
            if hasFiles {
                do { try FileManager.default.moveItem(at: staged, to: directory) } catch let restoreError {
                    throw AppFailure(
                        "Could not save the uninstall or restore the agent files: \(restoreError.localizedDescription). The files remain at \(staged.path)."
                    )
                }
            }
            throw error
        }
        if hasFiles {
            do { try FileManager.default.removeItem(at: staged) } catch {
                return AgentUninstallResult(
                    state: state,
                    cleanupError:
                        "The agent was unregistered, but its remaining files at \(staged.path) could not be removed: \(error.localizedDescription)"
                )
            }
        }
        return AgentUninstallResult(state: state, cleanupError: nil)
    }
    
    private func installAgent(_ agent: Agent) async throws -> InstalledAgent {
        let id = try PackageValidation.safeComponent(agent.id)
        let version = try PackageValidation.safeComponent(agent.version)
        let parent = root.appendingPathComponent("agents/\(id)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        // Build a fresh installation, then publish it atomically. Failed updates keep the old version.
        let staging = parent.appendingPathComponent(".staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let destination = parent.appendingPathComponent("\(version)-\(UUID().uuidString)")
        let distributionInstaller: any AgentDistributionInstalling
        if let binary = agent.binary {
            distributionInstaller = BinaryAgentInstaller(binary: binary, downloader: downloader)
        } else if let npm = agent.distribution.npx {
            distributionInstaller = NpmAgentInstaller(npm: npm, root: root, runtime: runtime)
        } else {
            throw AppFailure("This distribution is not supported on this Mac yet.")
        }
        let command = try await distributionInstaller.install(staging: staging, destination: destination)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
        return InstalledAgent(
            id: id, name: agent.name, version: version, executable: command.executable,
            arguments: command.arguments, environment: command.environment, directory: destination.path)
    }
}
