import CryptoKit
import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func appStoreUsesInjectedSnapshotRepositories() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-protocol-\(UUID())")
    let folder = root.appendingPathComponent("Project")
    let history = MemorySnapshotRepository<[ChatConversation]>(value: [])
    let projects = MemorySnapshotRepository<[URL]>(value: [folder])
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"),
        conversationRepository: history, projectRepository: projects)
    await store.load()
    store.newProjectChat(in: folder)
    store.messages = [.init(role: "user", text: "Keep this project chat")]
    store.checkpointConversation()
    await store.historySaveTask?.value
    await store.projectSaveTask?.value
    #expect(await history.load().first?.workspace == folder)
    #expect(await projects.load() == [folder])
    #expect(!FileManager.default.fileExists(atPath: root.path))
    let reopened = AppStore(stateURL: root.appendingPathComponent("state.json"),
        conversationRepository: history, projectRepository: projects)
    await reopened.load()
    reopened.openProject(folder)
    #expect(reopened.messages.first?.text == "Keep this project chat")
    await reopened.historySaveTask?.value
    await reopened.projectSaveTask?.value
}

@Test func sharedJSONRepositoryPreservesExistingFileFormatsAndRejectsCorruptData() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-json-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("projects.json")
    let repository: any SnapshotRepository<[URL]> = ProjectRepository(url: url)
    #expect(try await repository.load().isEmpty)
    let folders = [URL(fileURLWithPath: "/Projects/OneCap")]
    try await repository.save(folders)
    #expect(try JSONDecoder().decode([URL].self, from: Data(contentsOf: url)) == folders)
    let corrupt = Data("invalid".utf8)
    try corrupt.write(to: url)
    await #expect(throws: (any Error).self) { try await repository.load() }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func binaryAndNpmStrategiesUseTheSameContractAndInjectedServices() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-strategies-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let payload = Data("fixture".utf8)
    let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    let archive = FixtureArchive()
    let binary: any AgentDistributionInstalling = BinaryAgentInstaller(
        binary: .init(archive: "https://example.com/agent.zip", cmd: "agent", args: ["acp"], env: nil, sha256: hash),
        downloader: StaticDownload(value: payload), archive: archive)
    let npm: any AgentDistributionInstalling = NpmAgentInstaller(
        npm: .init(package: "example@1.0.0", args: ["--acp"], env: nil), root: root,
        runtime: FixtureRuntime(), runner: FixtureNpmRunner())
    var commands: [AgentCommand] = []
    for (index, strategy) in [binary, npm].enumerated() {
        let stage = root.appendingPathComponent("stage-\(index)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        commands.append(try await strategy.install(staging: stage, destination: root.appendingPathComponent("installed-\(index)")))
    }
    #expect(await archive.calls == 1)
    #expect(commands[0].executable == root.appendingPathComponent("installed-0/agent").path)
    #expect(commands[0].arguments == ["acp"])
    #expect(commands[1].executable == "/managed/bin/node")
    #expect(commands[1].arguments == [root.appendingPathComponent("installed-1/node_modules/example/cli.js").path, "--acp"])
}

private actor MemorySnapshotRepository<Value: Codable & Sendable>: SnapshotRepository {
    private var value: Value
    init(value: Value) { self.value = value }
    func load() -> Value { value }
    func save(_ value: Value) { self.value = value }
}

private struct StaticDownload: Downloading {
    let value: Data
    func data(_ url: URL) async throws -> Data { value }
}

private actor FixtureArchive: ArchiveExtracting {
    private(set) var calls = 0
    func unpack(_ data: Data, source: URL, to directory: URL, rawCommand: String) throws {
        calls += 1
        try data.write(to: directory.appendingPathComponent(rawCommand))
    }
}

private struct FixtureRuntime: NodeRuntimeProviding {
    func binary() async throws -> URL { URL(fileURLWithPath: "/managed/bin/node") }
}

private struct FixtureNpmRunner: ProcessRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]?) async throws -> String {
        #expect(executable == "/managed/bin/node")
        #expect(environment?["PATH"]?.hasPrefix("/managed/bin:") == true)
        let index = try #require(arguments.firstIndex(of: "--prefix"))
        let package = URL(fileURLWithPath: arguments[index + 1]).appendingPathComponent("node_modules/example")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"bin":"cli.js"}"#.utf8).write(to: package.appendingPathComponent("package.json"))
        try Data("console.log('fixture')".utf8).write(to: package.appendingPathComponent("cli.js"))
        return "Installed"
    }
}
