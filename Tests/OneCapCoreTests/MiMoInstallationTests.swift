import Foundation
import Testing

@testable import OneCapCore

@Test func mimoSupplementsCatalogAndDefersToFutureRegistryEntry() async throws {
    let agent = SupplementalAgentCatalog.mimo
    let empty = try JSONEncoder().encode(Registry(version: "1", agents: []))
    let catalog = try await AgentInstaller(downloader: MiMoDownload(payload: empty)).catalog()
    #expect(catalog.agents.map(\.id) == [agent.id])
    #expect(agent.canInstall)
    #expect(agent.distribution.binary?.count == 2)
    for binary in agent.distribution.binary?.values ?? [:].values {
        #expect(binary.sha256?.count == 64)
        #expect(binary.cmd == "./mimo" && binary.args == ["acp"])
    }
    let future = Agent(
        id: agent.id, name: agent.name, version: "1.0.0", description: "Upstream entry",
        repository: nil, website: nil, license: nil, distribution: agent.distribution)
    let payload = try JSONEncoder().encode(Registry(version: "2", agents: [future]))
    let updated = try await AgentInstaller(downloader: MiMoDownload(payload: payload)).catalog()
    #expect(updated.agents == [future])
}

@Test func mimoLegacyLoginUsesManagedBinaryAndLeavesOtherAgentsUnchanged() throws {
    let json: [String: Any] = [
        "id": "opencode-login", "name": "Login with opencode",
        "_meta": ["terminal-auth": ["command": "opencode", "args": ["auth", "login"]]],
    ]
    let agent = InstalledAgent(
        id: "mimocode", name: "MiMo Code", version: "0.1.16", executable: "/bin/echo",
        arguments: ["acp"], environment: [:], directory: "/tmp")
    let method = try #require(AuthMethod(json: json, agent: agent))
    let command = try TerminalLoginCommand(
        agent: agent, method: method, directory: URL(fileURLWithPath: "/tmp"))
    #expect(command.executable == agent.executable)
    #expect(command.arguments == ["auth", "login"])
    #expect(method.name == "Sign in to MiMo Code")
    #expect(AuthMethod(json: json)?.terminal?.command == "opencode")
    let other = InstalledAgent(
        id: "opencode", name: "OpenCode", version: "1", executable: "/bin/echo",
        arguments: ["acp"], environment: [:], directory: "/tmp")
    #expect(AuthMethod(json: json, agent: other)?.terminal?.command == "opencode")
    let modern = try #require(AuthMethod(json: [
        "id": "login", "name": "MiMo Login", "type": "terminal", "args": ["--login"],
    ], agent: agent))
    #expect(modern.name == "MiMo Login" && modern.terminal?.command == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_MIMO_ARCHIVE"] != nil))
@MainActor func officialMiMoArchiveInstallsAndCreatesACPSession() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-mimo-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let path = try #require(ProcessInfo.processInfo.environment["ONECAP_MIMO_ARCHIVE"])
    let archive = try Data(contentsOf: URL(fileURLWithPath: path))
    let installed = try await AgentInstaller(root: root, downloader: MiMoDownload(payload: archive))
        .install(SupplementalAgentCatalog.mimo)
    #expect(installed.arguments == ["acp"])
    #expect(FileManager.default.isExecutableFile(atPath: installed.executable))
    // Keep the real CLI's configuration and migration files inside the temporary test folder.
    let isolated = InstalledAgent(
        id: installed.id, name: installed.name, version: installed.version,
        executable: installed.executable, arguments: installed.arguments,
        environment: ["XDG_DATA_HOME": root.appendingPathComponent("data").path,
                      "XDG_CONFIG_HOME": root.appendingPathComponent("config").path,
                      "XDG_CACHE_HOME": root.appendingPathComponent("cache").path,
                      "XDG_STATE_HOME": root.appendingPathComponent("state").path],
        directory: installed.directory)
    let connection = ACPConnection()
    connection.onTerminalLogin = { _ in
        throw AppFailure("This integration check must not request credentials.")
    }
    defer { connection.close() }
    try await connection.connect(isolated, workspace: root)
    #expect(connection.connected)
    #expect(connection.authMethods.contains(where: { $0.terminal?.command == installed.executable }))
    try await connection.prepareSession()
    #expect(connection.sessionReady)
    #expect(connection.sessionOptions.contains(where: { $0.category == "model" }))
    #expect(connection.sessionOptions.contains(where: { $0.category == "mode" }))
}

private struct MiMoDownload: Downloading {
    let payload: Data
    func data(_ url: URL) async throws -> Data { payload }
}
