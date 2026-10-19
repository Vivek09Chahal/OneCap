import Foundation
import Testing

@testable import OneCapCore

@Test func decodesRegistryDistributionTypes() throws {
  let json =
    #"{"version":"1.0.0","agents":[{"id":"native","name":"Native","version":"1.2.3","description":"Test","distribution":{"binary":{"darwin-aarch64":{"archive":"https://example.com/a.zip","cmd":"./agent","sha256":"abc"}}}},{"id":"npm","name":"NPM","version":"2.0.0","description":"Test","distribution":{"npx":{"package":"@example/agent@2.0.0"}}},{"id":"python","name":"Python","version":"1.0.0","description":"Test","distribution":{"uvx":{"package":"agent"}}}] }"#
  let registry = try JSONDecoder().decode(Registry.self, from: Data(json.utf8))
  #expect(registry.agents.count == 3)
  #expect(registry.agents[1].canInstall)
  #expect(!registry.agents[2].canInstall)
}

@Test func rejectsPackagePathEscapes() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for unsafe in ["../escape", "/tmp/escape", "nested/../../escape", ""] {
    #expect(throws: AppFailure.self) { try PackageValidation.containedPath(unsafe, in: root) }
  }
  let link = root.appendingPathComponent("link")
  try FileManager.default.createSymbolicLink(
    at: link, withDestinationURL: URL(fileURLWithPath: "/tmp"))
  #expect(throws: AppFailure.self) { try PackageValidation.containedPath("link/escape", in: root) }
  #expect(
    try PackageValidation.containedPath("./bin/agent", in: root).path
      == root.appendingPathComponent("bin/agent").path)
}

@Test func verifiesArchiveChecksum() throws {
  let data = Data("abc".utf8)
  try PackageValidation.verify(
    data, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  #expect(throws: AppFailure.self) {
    try PackageValidation.verify(data, sha256: String(repeating: "0", count: 64))
  }
}

@Test func resolvesProviderEndpoint() throws {
  #expect(
    try ProviderClient.endpoint("https://example.com/v1/").absoluteString
      == "https://example.com/v1/chat/completions")
  for invalid in [
    "http://example.com", "https://user:secret@example.com", "https://example.com?key=secret",
    "https://example.com/#fragment",
  ] {
    #expect(throws: AppFailure.self) { try ProviderClient.endpoint(invalid) }
  }
}

@Test func parsesScopedAndUnscopedPackages() {
  #expect(NpmAgentInstaller.packageName("@scope/agent@1.2.3") == "@scope/agent")
  #expect(NpmAgentInstaller.packageName("agent@1.2.3") == "agent")
  #expect(NpmAgentInstaller.packageName("@scope/agent") == "@scope/agent")
}

@Test @MainActor func acpHandshakePromptAndDisconnect() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  // A tiny fake ACP server tests actual process I/O and session updates.
  let script = root.appendingPathComponent("agent.py")
  let source = #"""
    import json, sys
    def send(obj):
        print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        msg = json.loads(line)
        method = msg.get('method')
        if method == 'initialize':
            send({'jsonrpc':'2.0', 'id':msg['id'], 'result':{'protocolVersion':1, 'authMethods':[]}})
        elif method == 'session/new':
            send({'jsonrpc':'2.0', 'id':msg['id'], 'result':{'sessionId':'test-session'}})
        elif method == 'session/prompt':
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'test-session','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Hello from ACP'}}}})
            send({'jsonrpc':'2.0','id':msg['id'],'result':{'stopReason':'end_turn'}})
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let agent = InstalledAgent(
    id: "test", name: "Test", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  let connection = ACPConnection()
  var received = ""
  connection.onText = { received += $0 }
  try await connection.connect(agent, workspace: root)
  #expect(connection.connected)
  try await connection.prompt("Hello")
  #expect(received == "Hello from ACP")
  connection.close()
  #expect(!connection.connected)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_LIVE_INSTALL_TESTS"] == "1"))
func liveRegistryBinaryInstallation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-live-binary-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let installer = AgentInstaller(root: root)
  let registry = try await installer.catalog()
  let agent = try #require(registry.agents.first { $0.id == "opencode" })
  let installed = try await installer.install(agent)
  #expect(FileManager.default.isExecutableFile(atPath: installed.executable))
  #expect(installed.arguments == ["acp"])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_LIVE_INSTALL_TESTS"] == "1"))
func liveManagedNodePackageInstallation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-live-node-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let installer = AgentInstaller(root: root)
  let registry = try await installer.catalog()
  let agent = try #require(registry.agents.first { $0.id == "codex-acp" })
  let installed = try await installer.install(agent)
  #expect(FileManager.default.isExecutableFile(atPath: installed.executable))
  let entry = try #require(installed.arguments.first)
  #expect(FileManager.default.fileExists(atPath: entry))
  #expect(entry.hasPrefix(installed.directory + "/"))
}
