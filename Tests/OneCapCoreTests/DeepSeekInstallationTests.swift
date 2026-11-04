import Foundation
import Testing

@testable import OneCapCore

@Test func deepseekPreviewIsPinnedAndUpstreamEntryTakesPrecedence() async throws {
    let agent = SupplementalAgentCatalog.deepseek
    #expect(agent.version == "0.2.1-rc.5")
    #expect(agent.distribution.npx?.package == "@deepseek-ai/dsh@\(agent.version)")
    #expect(agent.distribution.npx?.args == ["--profile", "acp"])
    #expect(agent.canInstall && agent.distributionKind == .cli)
    #expect(agent.description.contains("Experimental"))
    #expect(agent.setupNote?.contains("credentials") == true)
    let future = Agent(
        id: agent.id, name: agent.name, version: "1.0.0", description: "Upstream entry",
        repository: agent.repository, website: agent.website, license: agent.license,
        distribution: agent.distribution)
    for entries in [[], [future]] {
        let payload = try JSONEncoder().encode(Registry(version: "1", agents: entries))
        let catalog = try await AgentInstaller(downloader: DeepSeekCatalogDownload(payload: payload)).catalog()
        #expect(catalog.agents.filter { $0.id == agent.id } == [entries.first ?? agent])
    }
}

@Test func deepseekNodeMinimumRejectsOlderAndMalformedVersions() {
    for version in ["v24.9.0\n", "24.22.0", "v26.0.0"] {
        #expect(NodeRuntime.supports(version))
    }
    for version in ["v22.22.0", "v24.8.9", "v24.9", "v24.9.0-rc.1", "invalid"] {
        #expect(!NodeRuntime.supports(version))
    }
}

@Test func cachedNodeIsProbedAndOlderRuntimeTriggersUpgrade() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-node-probe-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let runtimeRoot = root.appendingPathComponent("runtimes")
    try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
    try "/bin/echo".write(to: runtimeRoot.appendingPathComponent("node-path.txt"), atomically: true, encoding: .utf8)
    let downloader = DeepSeekCatalogDownload(payload: Data("[]".utf8))
    let current = NodeRuntime(root: root, downloader: downloader, runner: NodeVersionProbe(version: "v24.9.0"))
    #expect(try await current.binary().path == "/bin/echo")
    let older = NodeRuntime(root: root, downloader: downloader, runner: NodeVersionProbe(version: "v22.0.0"))
    // An empty release list fails after rejecting the cached runtime instead of returning it.
    await #expect(throws: AppFailure.self) { _ = try await older.binary() }
}

/// Opt in with a separately downloaded package; no model key or inference request is used.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_DEEPSEEK_PACKAGE"] != nil))
@MainActor func pinnedDeepSeekCreatesRealACPSession() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-deepseek-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let package = try #require(ProcessInfo.processInfo.environment["ONECAP_DEEPSEEK_PACKAGE"])
    let node = try #require(ProcessInfo.processInfo.environment["ONECAP_DEEPSEEK_NODE"])
    let agent = InstalledAgent(
        id: SupplementalAgentCatalog.deepseek.id, name: "DeepSeek Harness", version: "0.2.1-rc.5",
        executable: node, arguments: [package + "/lib/bin.js", "--profile", "acp"],
        environment: ["DSH_HOME": root.appendingPathComponent("harness").path,
                      "DSH_AGENTS_HOME": root.appendingPathComponent("agents").path,
                      "DEEPSEEK_API_KEY": ""], directory: root.path)
    let connection = ACPConnection()
    defer { connection.close() }
    try await connection.connect(agent, workspace: root)
    #expect(connection.connected)
    try await connection.prepareSession()
    #expect(connection.sessionReady)
}

private struct DeepSeekCatalogDownload: Downloading {
    let payload: Data
    func data(_ url: URL) async throws -> Data { payload }
}

private struct NodeVersionProbe: ProcessRunning {
    let version: String
    func run(_ executable: String, _ arguments: [String], environment: [String: String]?) async throws -> String {
        #expect(executable == "/bin/echo" && arguments == ["--version"])
        return version
    }
}
