import Foundation
import Testing
@testable import OneCapCore

@Test func codexCatalogKeepsTheRegistryACPAdapter() async throws {
    let entry = Agent(id: "codex-acp", name: "Codex", version: "1.2.3", description: "ACP adapter",
                      repository: "https://github.com/agentclientprotocol/codex-acp", website: nil, license: nil,
                      distribution: .init(binary: nil, npx: .init(package: "@agentclientprotocol/codex-acp@1.2.3", args: [], env: nil), uvx: nil))
    let payload = try JSONEncoder().encode(Registry(version: "1", agents: [entry]))
    let registry = try await AgentInstaller(downloader: ACPOnlyCatalogDownload(payload: payload)).catalog()
    let result = try #require(registry.agents.first)
    #expect(result.distribution.npx?.package == entry.distribution.npx?.package)
    #expect(result.version == entry.version)
    #expect(result.repository == entry.repository)
    #expect(result.distribution.npx?.args == [])
}

@Test @MainActor func restoresMigratedCodexLaunchSettingsToACPWithoutChangingSelection() async throws {
    let fixture = try ACPLaunchFixture()
    defer { fixture.cleanup() }
    let stateURL = fixture.root.appendingPathComponent("state.json")
    _ = try await AppRepository(url: stateURL).register(fixture.native)
    let store = AppStore(stateURL: stateURL)
    await store.load()
    let restored = try #require(store.installed.first)
    #expect(restored.id == fixture.native.id)
    #expect(restored.directory == fixture.native.directory)
    #expect(restored.environment == fixture.native.environment)
    #expect(restored.version == "1.2.3")
    #expect(restored.arguments == [fixture.entry.path])
    #expect(store.selectedAgentID == restored.id)
    #expect(store.connectionError == nil)
    #expect(try await AppRepository(url: stateURL).load().installed.first?.arguments == restored.arguments)
    #expect(try restored.acpLaunch().arguments == restored.arguments)
}

@Test @MainActor func nativeOnlyInstallRequiresReinstallationInsteadOfStartingAppServer() async throws {
    let fixture = try ACPLaunchFixture()
    defer { fixture.cleanup() }
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("node_modules"))
    let connection = ACPConnection()
    defer { connection.close() }
    do {
        try await connection.connect(fixture.native, workspace: fixture.root)
        Issue.record("A native-only executable was allowed to receive ACP messages")
    } catch {
        #expect(error.localizedDescription.contains("Reinstall Codex"))
        #expect(!connection.connected)
    }
}

private struct ACPLaunchFixture {
    let root: URL
    let entry: URL
    let native: InstalledAgent

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-restore-acp-" + UUID().uuidString)
        let package = root.appendingPathComponent("node_modules/@agentclientprotocol/codex-acp")
        entry = package.appendingPathComponent("bin/adapter.js")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// ACP adapter fixture".utf8).write(to: entry)
        try Data(#"{"name":"@agentclientprotocol/codex-acp","version":"1.2.3","bin":{"codex-acp":"bin/adapter.js"}}"#.utf8)
            .write(to: package.appendingPathComponent("package.json"))
        native = .init(id: "codex-acp", name: "Codex", version: "0.160.1", executable: "/usr/bin/node",
                       arguments: [root.appendingPathComponent("node_modules/@openai/codex/bin/codex.js").path, "app-server"],
                       environment: ["PRESERVED_SETTING": "value"], directory: root.path)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private struct ACPOnlyCatalogDownload: Downloading {
    let payload: Data
    func data(_ url: URL) async throws -> Data { payload }
}
