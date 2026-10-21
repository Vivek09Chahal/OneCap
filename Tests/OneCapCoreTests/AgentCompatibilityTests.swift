import Foundation
import Testing

@testable import OneCapCore

@Test func registryTabsMatchTheInstallersActualPreferredRoute() {
  let native = distributionAgent(binary: compatibleBinary(), npm: true)
  #expect(native.distributionKind == .binary)
  #expect(native.canInstall)
  let npm = distributionAgent(npm: true)
  #expect(npm.distributionKind == .cli)
  #expect(npm.canInstall)
  let python = distributionAgent(python: true)
  #expect(python.distributionKind == .cli)
  #expect(!python.canInstall)
  // A binary for a different OS must not override a managed CLI package on this Mac.
  let otherPlatform = Agent(
    id: "other-platform", name: "Other", version: "1", description: "", repository: nil,
    website: nil, license: nil,
    distribution: .init(
      binary: ["windows-x86_64": compatibleBinary()],
      npx: .init(package: "example@1", args: nil, env: nil), uvx: nil))
  #expect(otherPlatform.distributionKind == .cli)
  #expect(otherPlatform.canInstall)
}

@Test func unsupportedEntriesCannotBeOfferedAsInstallable() {
  #expect(!distributionAgent(id: "gemini", npm: true).canInstall)
  #expect(!distributionAgent(id: "amp-acp", binary: compatibleBinary()).canInstall)
  let noChecksum = BinaryDistribution(
    archive: "https://example.com/agent", cmd: "./agent", args: nil, env: nil, sha256: nil)
  #expect(!distributionAgent(binary: noChecksum).canInstall)
  let runtimeCommand = BinaryDistribution(
    archive: "https://example.com/agent.zip", cmd: "node", args: ["index.js"], env: nil,
    sha256: String(repeating: "a", count: 64))
  #expect(!distributionAgent(binary: runtimeCommand, npm: true).canInstall)
  #expect(!distributionAgent().canInstall)
}

@Test func blockedDefaultIsMigratedWithoutRemovingTheInstalledCopy() async throws {
  let root = compatibilityRoot()
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let gemini = compatibilityInstalled("gemini", command: "/managed/node")
  let supported = compatibilityInstalled("supported", command: "/managed/agent")
  let url = root.appendingPathComponent("state.json")
  try JSONEncoder().encode(
    SavedAppState(installed: [gemini, supported], selectedAgentID: gemini.id)
  ).write(to: url)
  let repository = AppRepository(url: url)
  let state = try await repository.load()
  #expect(state.selectedAgentID == supported.id)
  #expect(state.installed.count == 2)
  await #expect(throws: AppFailure.self) { try await repository.selectAgent(gemini.id) }
  let removed = try await repository.unregisterAgent(supported.id)
  #expect(removed.selectedAgentID == nil)
  #expect(removed.installed.map(\.id) == [gemini.id])
  #expect(gemini.distributionKind == .cli)
  #expect(supported.distributionKind == .binary)
}

@Test @MainActor func blockedAgentCannotStartLoginOrEraseTheCurrentDraft() async {
  let root = compatibilityRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  var openedBrowser = false
  let store = AppStore(
    stateURL: root.appendingPathComponent("state.json"),
    openLoginURL: { _ in
      openedBrowser = true
      return true
    })
  store.installed = [compatibilityInstalled("gemini", command: "/must-not-launch")]
  store.selectedAgentID = "gemini"
  store.chatUsesAgent = true
  store.draft = "Keep this draft"
  await store.connect()
  #expect(!store.acp.connected)
  #expect(!store.connecting)
  #expect(!openedBrowser)
  #expect(store.connectionError?.contains("Google") == true)
  #expect(store.draft == "Keep this draft")
}

@Test func blockedInstallDoesNotDownloadOrCreateAgentFiles() async {
  let root = compatibilityRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let downloader = CompatibilityDownloader()
  let installer = AgentInstaller(root: root, downloader: downloader)
  await #expect(throws: AppFailure.self) {
    _ = try await installer.install(distributionAgent(id: "gemini", npm: true))
  }
  #expect(await downloader.requests == 0)
  #expect(!FileManager.default.fileExists(atPath: root.path))
}

private func compatibleBinary() -> BinaryDistribution {
  .init(
    archive: "https://example.com/agent", cmd: "./agent", args: nil, env: nil,
    sha256: String(repeating: "a", count: 64))
}
private func distributionAgent(
  id: String = "example", binary: BinaryDistribution? = nil, npm: Bool = false, python: Bool = false
) -> Agent {
  .init(
    id: id, name: id, version: "1", description: "", repository: nil, website: nil, license: nil,
    distribution: .init(
      binary: binary.map { [Agent.platform: $0] },
      npx: npm ? .init(package: "example@1", args: nil, env: nil) : nil,
      uvx: python ? .init(package: "example", args: nil, env: nil) : nil))
}
private func compatibilityInstalled(_ id: String, command: String) -> InstalledAgent {
  .init(
    id: id, name: id, version: "1", executable: command, arguments: [], environment: [:],
    directory: "/managed/\(id)")
}
private func compatibilityRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-compatibility-\(UUID().uuidString)")
}
private actor CompatibilityDownloader: Downloading {
  var payload = Data()
  var requests = 0
  init(payload: Data = Data()) { self.payload = payload }
  func setPayload(_ payload: Data) { self.payload = payload }
  func data(_ url: URL) async throws -> Data {
    requests += 1
    return payload
  }
}

@Test @MainActor func catalogRefreshKeepsLastSuccessfulTimeAndAgentsOnFailure() async throws {
  let entry = distributionAgent(npm: true)
  let downloader = CompatibilityDownloader(payload: try JSONEncoder().encode(
    Registry(version: "1", agents: [entry])))
  let store = AppStore(installer: AgentInstaller(downloader: downloader))
  #expect(store.catalogUpdatedAt == nil && !store.catalogRefreshFailed)
  await store.refresh()
  let refreshedAt = try #require(store.catalogUpdatedAt)
  #expect(store.agents.count == 1 && !store.catalogRefreshFailed && !store.loading)
  await downloader.setPayload(Data("invalid catalog".utf8))
  await store.refresh()
  #expect(store.catalogUpdatedAt == refreshedAt)
  #expect(store.agents.first?.id == entry.id && store.catalogRefreshFailed && !store.loading)
  await downloader.setPayload(try JSONEncoder().encode(Registry(version: "2", agents: [])))
  await store.refresh()
  #expect(store.agents.isEmpty && !store.catalogRefreshFailed)
  #expect(try #require(store.catalogUpdatedAt) >= refreshedAt)
}

@Test func retiredKimiCatalogEntryUsesKimiCodeWithoutChangingItsID() async throws {
  let old = Agent(
    id: "kimi", name: "Kimi CLI", version: "1.52.0", description: "Old agent",
    repository: "https://github.com/MoonshotAI/kimi-cli", website: nil, license: "MIT",
    distribution: .init(binary: nil, npx: nil, uvx: .init(package: "kimi-cli", args: nil, env: nil)),
    icon: "https://cdn.agentclientprotocol.com/registry/v1/latest/kimi.svg")
  let other = distributionAgent(npm: true)
  let payload = try JSONEncoder().encode(Registry(version: "1", agents: [old, other]))
  let registry = try await AgentInstaller(downloader: CompatibilityDownloader(payload: payload)).catalog()
  let kimi = try #require(registry.agents.first)
  #expect(kimi.id == old.id && kimi.icon == old.icon)
  #expect(kimi.name == "Kimi Code CLI" && kimi.version == "2.2.0")
  #expect(kimi.repository == "https://github.com/MoonshotAI/kimi-code")
  #expect(kimi.canInstall && kimi.distribution.npx == nil && kimi.distribution.uvx == nil)
  #expect(kimi.distribution.binary?.count == 2)
  for binary in kimi.distribution.binary?.values ?? [:].values {
    #expect(binary.archive.hasPrefix("https://code.kimi.com/kimi-code/binaries/2.2.0/"))
    #expect(binary.cmd == "./kimi" && binary.args == ["acp"])
    #expect(binary.sha256?.count == 64)
  }
  #expect(registry.agents.last?.version == other.version)
  // Once the registry switches repositories, respect its future versions and distribution.
  let updated = Registry(version: "2", agents: [Agent(
    id: "kimi", name: "Kimi Code CLI", version: "3.0.0", description: "New registry release",
    repository: kimi.repository, website: kimi.website, license: kimi.license,
    distribution: other.distribution)])
  let future = try await AgentInstaller(downloader: CompatibilityDownloader(
    payload: JSONEncoder().encode(updated))).catalog()
  #expect(future.agents.first?.version == "3.0.0")
}
