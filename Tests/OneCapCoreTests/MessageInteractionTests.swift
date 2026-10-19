import Foundation
import Testing

@testable import OneCapCore

@Test func thinkingTimeFreezesOnFirstStopAndDecodesLegacyMessages() throws {
  let start = Date(timeIntervalSince1970: 100)
  var timing = ThinkingTime(startedAt: start)
  #expect(timing.elapsed(at: start.addingTimeInterval(2.5)) == 2.5)
  #expect(timing.isRunning)
  timing.stop(at: start.addingTimeInterval(3))
  timing.stop(at: start.addingTimeInterval(9))
  #expect(!timing.isRunning)
  #expect(timing.elapsed(at: start.addingTimeInterval(100)) == 3)
  var early = ThinkingTime(startedAt: start)
  early.stop(at: start.addingTimeInterval(-1))
  #expect(early.elapsed() == 0)
  let json = Data(
    #"{"id":"00000000-0000-0000-0000-000000000001","role":"user","text":"Hello"}"#.utf8)
  let message = try JSONDecoder().decode(ChatMessage.self, from: json)
  #expect(message.text == "Hello")
  #expect(message.thinkingTime == nil)
}

@Test @MainActor func onlyLatestUserMessageCanBeEditedWithoutMutatingOnCancel() {
  let store = AppStore()
  store.messages = [
    .init(role: "user", text: "First"), .init(role: "assistant", text: "Answer"),
    .init(role: "user", text: "Last"), .init(role: "assistant", text: "Last answer"),
  ]
  store.beginEditing(store.messages[0].id)
  #expect(store.editingMessageID == nil)
  store.beginEditing(store.messages[3].id)
  #expect(store.editingMessageID == nil)
  let lastID = store.messages[2].id
  store.beginEditing(lastID)
  #expect(store.editingMessageID == lastID)
  store.editedMessageText = "  \n "
  #expect(!store.saveEditedMessage())
  #expect(store.messages[2].text == "Last")
  store.editedMessageText = "Changed"
  store.cancelEditing()
  #expect(store.messages[2].text == "Last")
  #expect(store.messages.count == 4)
  store.sending = true
  #expect(!store.canEditMessage(lastID))
  store.beginEditing(lastID)
  #expect(store.editingMessageID == nil)
  store.sending = false
  store.connecting = true
  #expect(!store.canEditMessage(lastID))
}

@Test @MainActor func editingRestartsAgentSessionWithEarlierContextAndFreezesStreamingTimer()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-edit-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let script = root.appendingPathComponent("agent.py")
  let source = #"""
    import json, sys, time
    sessions = 0
    def send(obj):
        print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        method = m.get('method')
        if method == 'initialize':
            send({'jsonrpc':'2.0','id':m['id'],'result':{'protocolVersion':1}})
        elif method == 'session/new':
            sessions += 1
            send({'jsonrpc':'2.0','id':m['id'],'result':{'sessionId':str(sessions)}})
        elif method == 'session/prompt':
            blocks = m['params']['prompt']
            text = blocks[-1]['text']
            result = {'earlier':'prior answer','original':'old answer'}.get(text, 'invalid context')
            if text == 'revised' and sessions == 2 and len(blocks) == 2:
                send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'1','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Stale answer'}}}})
                context = blocks[0]['text']
                if 'earlier' in context and 'prior answer' in context and 'original' not in context and 'old answer' not in context:
                    result = 'revised answer'
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':result}}}})
            time.sleep(0.3)
            send({'jsonrpc':'2.0','id':m['id'],'result':{'stopReason':'end_turn'}})
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let agent = InstalledAgent(
    id: "edit-test", name: "Test", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  store.installed = [agent]
  store.selectedAgentID = agent.id
  store.chatUsesAgent = true
  store.workspace = root
  await store.connect()
  defer { store.resetChat() }
  #expect(store.acp.sessionReady)
  store.send("earlier", useAgent: true)
  try await waitForMessageInteraction { !store.sending }
  store.send("original", useAgent: true)
  try await waitForMessageInteraction { !store.sending }
  let earlierIDs = store.messages.prefix(2).map(\.id)
  let latestID = try #require(store.lastUserMessageID)
  store.draft = "Unsent draft"
  store.beginEditing(latestID)
  store.editedMessageText = "revised"
  #expect(store.saveEditedMessage())
  #expect(store.editingMessageID == nil)
  #expect(!store.canEditMessage(latestID))
  #expect(store.messages.map(\.text) == ["earlier", "prior answer", "revised", ""])
  try await waitForMessageInteraction { store.messages.last?.text == "revised answer" }
  #expect(store.sending)
  let timing = try #require(store.messages.last?.thinkingTime)
  #expect(!timing.isRunning)
  let frozen = timing.elapsed()
  try await waitForMessageInteraction { !store.sending }
  #expect(store.messages.last?.thinkingTime?.elapsed() == frozen)
  #expect(store.messages.last?.replyState == .completed)
  #expect(store.messages.prefix(2).map(\.id) == earlierIDs)
  #expect(store.messages.count == 4)
  #expect(store.draft == "Unsent draft")
  #expect(store.error == nil)
  #expect(store.canEditMessage(latestID))
}

@MainActor private func waitForMessageInteraction(_ condition: () -> Bool) async throws {
  for _ in 0..<500 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw AppFailure("Timed out waiting for message interaction.")
}
