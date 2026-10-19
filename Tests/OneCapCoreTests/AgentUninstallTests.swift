import CryptoKit
import Foundation
import Testing

@testable import OneCapCore

@Test func uninstallRemovesAllManagedVersionsAndPreservesUnrelatedData() async throws {
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let data = Data("mock agent executable".utf8)
  let installer = AgentInstaller(root: root, downloader: UninstallDownloader(data: data))
  let first = try await installer.install(uninstallCatalogAgent(version: "1", data: data))
  let latest = try await installer.install(uninstallCatalogAgent(version: "2", data: data))
  let stateURL = root.appendingPathComponent("state.json")
  let provider = Provider(name: "Saved provider", baseURL: "https://example.com", model: "model")
  try JSONEncoder().encode(
    SavedAppState(installed: [latest], providers: [provider], selectedAgentID: latest.id)
  )
  .write(to: stateURL)
  let repository = AppRepository(url: stateURL)
  let outside = root.appendingPathComponent("external-login")
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  let paths = [
    "runtimes/node", "npm-cache/cache", "agents/other/version/agent", "external-login/token",
    "conversations.json",
  ]
  for path in paths { try writeUninstallFixture(root.appendingPathComponent(path)) }
  // Uninstall must derive ownership from the managed root, ignoring an untrusted saved directory.
  let record = InstalledAgent(
    id: latest.id, name: latest.name, version: latest.version,
    executable: latest.executable, arguments: [], environment: [:], directory: outside.path)
  _ = try await repository.register(record)
  let result = try await installer.uninstall(record, repository: repository)
  #expect(result.cleanupError == nil)
  #expect(!FileManager.default.fileExists(atPath: first.directory))
  #expect(!FileManager.default.fileExists(atPath: latest.directory))
  for path in paths {
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
  }
  #expect(result.state.installed.isEmpty)
  #expect(result.state.selectedAgentID == nil)
  #expect(result.state.providers == [provider])
  #expect(try await AppRepository(url: stateURL).load().installed.isEmpty)
  // A successful uninstall must also release the installer lock for reinstall.
  let reinstalled = try await installer.install(uninstallCatalogAgent(version: "2", data: data))
  #expect(FileManager.default.fileExists(atPath: reinstalled.directory))
}

@Test func uninstallRollsBackFilesWhenSettingsCannotBeSaved() async throws {
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let agent = try makeInstalledAgent("first", root: root)
  let stateURL = root.appendingPathComponent("state.json")
  let repository = AppRepository(url: stateURL)
  _ = try await repository.register(agent)
  try FileManager.default.removeItem(at: stateURL)
  try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
  do {
    _ = try await AgentInstaller(root: root).uninstall(agent, repository: repository)
    Issue.record("Uninstall should fail when the settings path is a directory.")
  } catch {}
  #expect(FileManager.default.fileExists(atPath: agent.directory))
  #expect(FileManager.default.fileExists(atPath: agent.executable))
  #expect(try await repository.load().installed.map(\.id) == [agent.id])
}

@Test(arguments: [false, true]) func uninstallRejectsSymlinkedManagedPaths(parent: Bool)
  async throws
{
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let outside = root.appendingPathComponent("outside")
  try writeUninstallFixture(outside.appendingPathComponent("keep"))
  let managed = root.appendingPathComponent("agents")
  if !parent {
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
  }
  try FileManager.default.createSymbolicLink(
    at: parent ? managed : managed.appendingPathComponent("first"), withDestinationURL: outside)
  let record = InstalledAgent(
    id: "first", name: "First", version: "1", executable: "/bin/echo", arguments: [],
    environment: [:], directory: outside.path)
  let repository = AppRepository(url: root.appendingPathComponent("state.json"))
  _ = try await repository.register(record)
  await #expect(throws: AppFailure.self) {
    _ = try await AgentInstaller(root: root).uninstall(record, repository: repository)
  }
  #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep").path))
  #expect(try await repository.load().installed.map(\.id) == ["first"])
}

@Test func unregisterSelectsFallbackAndPreservesAnUnrelatedDefault() async throws {
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = AppRepository(url: root.appendingPathComponent("state.json"))
  for id in ["first", "second", "third"] {
    _ = try await repository.register(makeInstalledAgent(id, root: root))
  }
  try await repository.selectAgent("second")
  let removedOther = try await repository.unregisterAgent("third")
  #expect(removedOther.selectedAgentID == "second")
  let removedDefault = try await repository.unregisterAgent("second")
  #expect(removedDefault.selectedAgentID == "first")
  let removedLast = try await repository.unregisterAgent("first")
  #expect(removedLast.selectedAgentID == nil)
}

@Test @MainActor func uninstallingSelectedAgentArchivesChatAndChoosesTheNextAgent() async throws {
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AppStore(
    stateURL: root.appendingPathComponent("state.json"), installer: AgentInstaller(root: root))
  await store.load()
  let files = try makeInstalledAgent("first", root: root)
  let script = URL(fileURLWithPath: files.directory).appendingPathComponent("agent.py")
  let source = #"""
    import json, sys
    for line in sys.stdin:
        m = json.loads(line)
        result = {'protocolVersion':1} if m.get('method') == 'initialize' else {'sessionId':'idle'}
        if 'id' in m:
            print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':result}), flush=True)
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let first = InstalledAgent(
    id: files.id, name: files.name, version: files.version,
    executable: "/usr/bin/python3", arguments: ["-u", script.path], environment: [:],
    directory: files.directory)
  let second = try makeInstalledAgent("second", root: root)
  _ = try await store.repository.register(first)
  let state = try await store.repository.register(second)
  store.installed = state.installed
  store.selectedAgentID = first.id
  store.chatUsesAgent = true
  await store.connect()
  #expect(store.acp.sessionReady)
  store.messages = [
    .init(role: "user", text: "Saved question"), .init(role: "assistant", text: "Saved answer"),
  ]
  store.draft = "Unsent draft"
  let conversationID = store.conversationID
  await store.uninstallAgent(first.id)
  #expect(store.selectedAgentID == second.id)
  #expect(store.installed.map(\.id) == [second.id])
  #expect(store.messages.isEmpty)
  #expect(
    store.conversations.first(where: { $0.id == conversationID })?.messages.map(\.text) == [
      "Saved question", "Saved answer",
    ])
  #expect(store.conversations.first(where: { $0.id == conversationID })?.draft == "Unsent draft")
  #expect(store.conversations.first(where: { $0.id == conversationID })?.agentID == first.id)
  #expect(!store.acp.connected)
  await store.uninstallAgent(second.id)
  #expect(store.selectedAgentID == nil)
  #expect(store.installed.isEmpty)
  #expect(store.uninstalling.isEmpty)
  #expect(store.error == nil)
  await store.historySaveTask?.value
  let reloaded = try await AppRepository(url: root.appendingPathComponent("state.json")).load()
  #expect(reloaded.installed.isEmpty)
  #expect(reloaded.selectedAgentID == nil)
}

@Test @MainActor func uninstallDoesNotResetProviderChatAndRefusesBusyAgents() async throws {
  let root = uninstallRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let agent = try makeInstalledAgent("first", root: root)
  let store = AppStore(
    stateURL: root.appendingPathComponent("state.json"), installer: AgentInstaller(root: root))
  store.installed = try await store.repository.register(agent).installed
  store.selectedAgentID = agent.id
  store.chatUsesAgent = false
  store.messages = [.init(role: "user", text: "Provider question")]
  store.draft = "Provider draft"
  let chatID = store.conversationID
  store.sending = true
  await store.uninstallAgent(agent.id)
  #expect(FileManager.default.fileExists(atPath: agent.directory))
  store.sending = false
  store.installing.insert(agent.id)
  await store.uninstallAgent(agent.id)
  #expect(store.installed.count == 1)
  store.installing.remove(agent.id)
  await store.uninstallAgent(agent.id)
  #expect(store.conversationID == chatID)
  #expect(store.messages.map(\.text) == ["Provider question"])
  #expect(store.draft == "Provider draft")
  #expect(store.installed.isEmpty)
  #expect(store.error == nil)
}

private func uninstallRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-uninstall-\(UUID().uuidString)")
}
private func writeUninstallFixture(_ url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data("keep".utf8).write(to: url)
}
private func makeInstalledAgent(_ id: String, root: URL) throws -> InstalledAgent {
  let directory = root.appendingPathComponent("agents/\(id)/1")
  let executable = directory.appendingPathComponent("agent")
  try writeUninstallFixture(executable)
  return InstalledAgent(
    id: id, name: id, version: "1", executable: executable.path, arguments: [], environment: [:],
    directory: directory.path)
}
private func uninstallCatalogAgent(version: String, data: Data) -> Agent {
  let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  return Agent(
    id: "test", name: "Test", version: version, description: "", repository: nil, website: nil,
    license: nil,
    distribution: .init(
      binary: [
        Agent.platform: .init(
          archive: "https://example.com/agent", cmd: "./agent", args: nil, env: nil, sha256: hash)
      ], npx: nil, uvx: nil))
}
private struct UninstallDownloader: Downloading {
  let data: Data
  func data(_ url: URL) async throws -> Data { data }
}
