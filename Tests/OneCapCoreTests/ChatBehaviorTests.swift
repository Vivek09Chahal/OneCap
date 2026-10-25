import CryptoKit
import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func firstInstalledAgentBecomesDefaultAndLaterInstallsPreserveIt() async throws {
  let root = chatTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let data = Data("mock executable".utf8)
  let installer = AgentInstaller(root: root, downloader: ChatFixtureDownloader(response: data))
  let stateURL = root.appendingPathComponent("state.json")
  let store = AppStore(stateURL: stateURL, installer: installer)
  await store.load()
  await store.install(registryAgent("first", data: data))
  #expect(store.selectedAgentID == "first")
  #expect(store.chatUsesAgent)
  await store.install(registryAgent("second", data: data))
  #expect(store.selectedAgentID == "first")
  let reopened = AppStore(stateURL: stateURL)
  await reopened.load()
  #expect(reopened.selectedAgentID == "first")
  #expect(reopened.chatUsesAgent)
  try await reopened.repository.selectAgent("second")
  let selected = AppStore(stateURL: stateURL)
  await selected.load()
  #expect(selected.selectedAgentID == "second")
}

@Test func existingSettingsWithoutDefaultSelectTheFirstInstalledAgent() async throws {
  let root = chatTestRoot()
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("state.json")
  let legacy =
    #"{"installed":[{"id":"existing","name":"Existing","version":"1","executable":"/bin/echo","arguments":[],"environment":{},"directory":"/tmp"}],"providers":[]}"#
  try Data(legacy.utf8).write(to: url)
  let state = try await AppRepository(url: url).load()
  #expect(state.selectedAgentID == "existing")
}

@Test @MainActor func stopKeepsTranscriptDraftAndAgentSession() async throws {
  let root = chatTestRoot()
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let script = root.appendingPathComponent("agent.py")
  // The second prompt only succeeds if cancellation kept the original ACP session.
  let source = #"""
    import json, sys
    active = None
    sessions = 0
    def send(obj):
        print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        method = m.get('method')
        if method == 'initialize':
            send({'jsonrpc':'2.0', 'id':m['id'], 'result':{'protocolVersion':1}})
        elif method == 'session/new':
            sessions += 1
            send({'jsonrpc':'2.0', 'id':m['id'], 'result':{'sessionId':'kept-session'}})
        elif method == 'session/prompt':
            text = m['params']['prompt'][0]['text']
            content = 'Partial reply' if text == 'first' else 'Session preserved' if sessions == 1 else 'Session lost'
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'kept-session','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':content}}}})
            if text == 'first':
                active = m['id']
            else:
                send({'jsonrpc':'2.0','id':m['id'],'result':{'stopReason':'end_turn'}})
        elif method == 'session/cancel' and active is not None:
            send({'jsonrpc':'2.0','id':active,'result':{'stopReason':'cancelled'}})
            active = None
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let agent = InstalledAgent(
    id: "test", name: "Test", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  store.installed = [agent]
  store.selectedAgentID = agent.id
  store.chatUsesAgent = true
  store.workspace = root
  await store.connect()
  store.draft = "An unsent draft"
  store.send("first", useAgent: true)
  try await waitForChat { store.messages.last?.text == "Partial reply" }
  store.stopReply()
  try await waitForChat { !store.sending }
  #expect(store.acp.connected)
  #expect(store.messages.map(\.text) == ["first", "Partial reply"])
  #expect(store.draft == "An unsent draft")
  #expect(store.error == nil)
  store.send("second", useAgent: true)
  try await waitForChat { !store.sending }
  #expect(store.messages.last?.text == "Session preserved")
  store.resetChat()
  #expect(store.messages.isEmpty)
}

@Test @MainActor func stopProviderReplyKeepsExistingConversation() async throws {
  let root = chatTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
  store.providers = [provider]
  store.selectedProviderID = provider.id
  store.messages = [
    .init(role: "user", text: "Earlier question"), .init(role: "assistant", text: "Earlier answer"),
  ]
  store.draft = "Unsent draft"
  // Cancel before credentials/network work begins, with the same task lifecycle as provider chat.
  store.send("New question", useAgent: false)
  store.stopReply()
  try await waitForChat { !store.sending }
  #expect(store.messages.map(\.text) == ["Earlier question", "Earlier answer", "New question"])
  #expect(store.draft == "Unsent draft")
  #expect(store.error == nil)
}

@MainActor private func waitForChat(_ condition: () -> Bool) async throws {
  for _ in 0..<300 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw AppFailure("Timed out waiting for the test chat state.")
}

private func chatTestRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-chat-\(UUID().uuidString)")
}
private struct ChatFixtureDownloader: Downloading {
  let response: Data
  func data(_ url: URL) async throws -> Data { response }
}
private func registryAgent(_ id: String, data: Data) -> Agent {
  let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  return Agent(
    id: id, name: id, version: "1", description: "", repository: nil, website: nil, license: nil,
    distribution: .init(
      binary: [
        Agent.platform: .init(
          archive: "https://example.com/agent", cmd: "./agent", args: nil, env: nil, sha256: hash)
      ], npx: nil, uvx: nil))
}

@Test @MainActor func agentChatWorksWithoutSelectingAFolder() async throws {
  let root = chatTestRoot()
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let script = root.appendingPathComponent("folderless-agent.py")
  let source = #"""
    import json, os, sys
    def send(obj):
        print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        if m.get('method') == 'initialize':
            send({'jsonrpc':'2.0', 'id':m['id'], 'result':{'protocolVersion':1}})
        elif m.get('method') == 'session/new':
            cwd = m['params']['cwd']
            if not os.path.isdir(cwd) or os.path.realpath(cwd) != os.path.realpath(os.getcwd()):
                send({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32602,'message':'Invalid working directory'}})
            else:
                send({'jsonrpc':'2.0','id':m['id'],'result':{'sessionId':'chat-only'}})
        elif m.get('method') == 'session/prompt':
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'chat-only','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Chat works without a project folder'}}}})
            send({'jsonrpc':'2.0','id':m['id'],'result':{'stopReason':'end_turn'}})
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  let agent = InstalledAgent(
    id: "folderless", name: "Test", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  store.installed = [agent]
  store.selectedAgentID = agent.id
  store.chatUsesAgent = true
  #expect(store.workspace == nil)
  await store.connect()
  defer { store.resetChat() }
  #expect(store.acp.connected)
  #expect(store.workspace == nil)
  store.send("Hello", useAgent: true)
  try await waitForChat { !store.sending }
  #expect(store.error == nil)
  #expect(store.messages.last?.text == "Chat works without a project folder")
}

@Test func chatDirectoryUsesSelectedFolderAndIsolatesConversations() async throws {
  let root = chatTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let directories = ChatWorkspaceDirectory(root: root)
  let firstID = UUID()
  let first = try await directories.resolve(selected: nil, conversationID: firstID)
  let same = try await directories.resolve(selected: nil, conversationID: firstID)
  let next = try await directories.resolve(selected: nil, conversationID: UUID())
  #expect(first == same)
  #expect(first != next)
  #expect(FileManager.default.fileExists(atPath: first.path))
  let selected = root.appendingPathComponent("project")
  #expect(try await directories.resolve(selected: selected, conversationID: firstID) == selected)
}
