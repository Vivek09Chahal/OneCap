import Foundation
import Testing

@testable import OneCapCore

@Test func toolActivityMergesPartialUpdatesAndEndsOnCompletionOrFailure() {
  var activity = ACPToolActivity(id: "edit")
  activity.merge(["kind": "edit", "title": "Editing ChatComposer.swift", "status": "in_progress"])
  #expect(activity.isActive)
  #expect(activity.label == "Editing ChatComposer.swift")
  #expect(activity.phase == "Editing files")
  activity.merge(["status": "completed"])
  #expect(!activity.isActive)
  #expect(activity.label == "Editing ChatComposer.swift")
  var command = ACPToolActivity(id: "command")
  command.merge(["kind": "execute"])
  #expect(command.label == "Running command in terminal")
  command.merge(["title": "swift -typecheck App.swift"])
  #expect(command.phase == "Running command in terminal")
  #expect(command.label == "swift -typecheck App.swift")
  #expect(command.isActive)
  command.merge(["status": "failed"])
  #expect(!command.isActive)
}

@Test @MainActor func fileEditsAppearWhilePendingAndRetainPathsAcrossPartialUpdates() {
  let connection = ACPConnection()
  var command = ACPToolActivity(id: "command")
  command.merge(["kind": "execute", "title": "swift build", "status": "completed"])
  var edit = ACPToolActivity(id: "edit")
  edit.merge(["kind": "edit", "title": "apply_patch",
              "locations": [["path": "Sources/App.swift"], ["path": "Sources/App.swift"],
                            ["path": "Sources/View.swift"]]])
  connection.toolActivities = [command, edit]
  #expect(connection.currentToolActivity?.id == "edit")
  #expect(connection.currentToolActivity?.label == "Editing Sources/App.swift, Sources/View.swift")
  edit.merge(["status": "in_progress"])
  #expect(edit.filePaths == ["Sources/App.swift", "Sources/View.swift"])
  connection.toolActivities[1] = edit
  #expect(connection.currentToolActivity?.phase == "Editing files")
  edit.merge(["status": "completed"])
  connection.toolActivities[1] = edit
  #expect(connection.currentToolActivity == nil)
  var unnamed = ACPToolActivity(id: "unnamed")
  unnamed.merge(["kind": "edit", "title": "apply_patch"])
  #expect(unnamed.label == "Editing files: apply_patch")
}

@Test @MainActor func commandHistorySurvivesCheckpointWithoutSavingRunningStatuses() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-tools-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  let activities = [
    ACPToolActivity(id: "fast", title: "pwd", kind: "execute", status: "completed"),
    ACPToolActivity(id: "error", title: "exit 1", kind: "execute", status: "failed"),
    ACPToolActivity(id: "running", title: "swift build", kind: "execute", status: "in_progress"),
  ]
  store.messages = [
    .init(role: "user", text: "Run commands"),
    .init(role: "assistant", text: "", replyState: .responding, toolActivities: activities),
  ]
  store.checkpointConversation()
  let saved = try #require(store.conversations.first?.messages.last)
  #expect(saved.toolActivities?.map(\.status) == ["completed", "failed", "stopped"])
  #expect(store.messages.last?.toolActivities?.last?.isActive == true)
  #expect(ChatTranscriptEntry.make(from: store.messages).count == 2)
  let data = try JSONEncoder().encode(saved)
  #expect(try JSONDecoder().decode(ChatMessage.self, from: data) == saved)
  await store.historySaveTask?.value
}

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
  #expect(message.toolActivities == nil)
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
            for sid, thought in [(str(sessions), 'Checking '), ('stale', 'Ignore this'), (str(sessions), 'the files.')]:
                send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':sid,'update':{'sessionUpdate':'agent_thought_chunk','content':{'type':'text','text':thought}}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':result}}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'tool_call','toolCallId':'fast','kind':'execute','title':'pwd','status':'in_progress'}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'tool_call_update','toolCallId':'fast','status':'completed'}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'tool_call','toolCallId':'edit','kind':'edit','title':'Editing example.swift','status':'in_progress'}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'stale','update':{'sessionUpdate':'tool_call','toolCallId':'stale','title':'Wrong session','status':'in_progress'}}})
            time.sleep(0.3)
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':str(sessions),'update':{'sessionUpdate':'tool_call_update','toolCallId':'edit','status':'completed'}}})
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
  try await waitForMessageInteraction { store.acp.activitySummary == "Editing example.swift" }
  #expect(store.acp.activityPhase == "Editing files")
  #expect(store.messages.last?.toolActivities?.map(\.id) == ["fast", "edit"])
  #expect(store.messages.last?.toolActivities?.first?.status == "completed")
  let timing = try #require(store.messages.last?.thinkingTime)
  #expect(!timing.isRunning)
  let frozen = timing.elapsed()
  try await waitForMessageInteraction { !store.sending }
  #expect(store.messages.last?.thinkingTime?.elapsed() == frozen)
  #expect(store.messages.last?.replyState == .completed)
  #expect(store.acp.activitySummary == nil)
  #expect(store.acp.activityPhase == nil)
  #expect(store.messages.prefix(2).map(\.id) == earlierIDs)
  #expect(store.messages.count == 4)
  let activities = try #require(store.messages.last?.toolActivities)
  #expect(activities.map(\.id) == ["fast", "edit"])
  #expect(activities.allSatisfy { $0.status == "completed" })
  #expect(store.messages[1].toolActivities?.map(\.id) == ["fast", "edit"])
  let saved = try JSONEncoder().encode(store.messages)
  let restored = try JSONDecoder().decode([ChatMessage].self, from: saved)
  #expect(restored.last?.toolActivities == activities)
  #expect(store.messages.last?.thoughtText == "Checking the files.")
  #expect(restored.last?.thoughtText == "Checking the files.")
  #expect(store.messages.last?.text == "revised answer")
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

@Test func thoughtOnlyRepliesPersistAndOldMessagesStillDecode() throws {
  let legacy = Data(#"{"role":"assistant","text":"Saved reply","id":"00000000-0000-0000-0000-000000000001"}"#.utf8)
  let old = try JSONDecoder().decode(ChatMessage.self, from: legacy)
  #expect(old.thoughtText == nil)
  let thought = ChatMessage(role: "assistant", text: "", replyState: .completed, thoughtText: "Checking files")
  #expect(thought.hasContent)
  #expect(ChatTranscriptEntry.make(from: [thought]).count == 1)
  let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(thought))
  #expect(restored.thoughtText == thought.thoughtText)
  #expect(thought.contentForModel.isEmpty)
  let running = ChatMessage(role: "assistant", text: "", replyState: .thinking)
  #expect(ChatTranscriptEntry.make(from: [running]).count == 1)
}
