import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func newChatClearsFolderAndPreservesPreviousProjectHistory() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-new-chat-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  await store.load()
  let folder = root.appendingPathComponent("Project")
  store.workspace = folder
  store.selectedAgentID = "codex"
  store.chatUsesAgent = true
  store.draft = "Keep this project draft"
  let projectID = store.conversationID

  store.newChat()
  #expect(store.workspace == nil)
  #expect(store.conversationID != projectID)
  #expect(store.draft.isEmpty)
  #expect(store.messages.isEmpty)
  #expect(store.selectedAgentID == "codex")
  #expect(store.chatUsesAgent)
  #expect(store.conversations.first(where: { $0.id == projectID })?.workspace == folder)
  #expect(store.conversations.first(where: { $0.id == projectID })?.draft == "Keep this project draft")

  let standaloneID = store.conversationID
  store.draft = "A standalone chat"
  store.newProjectChat(in: folder)
  #expect(store.workspace == folder.standardizedFileURL)
  #expect(store.conversations.historyChats.map(\.id) == [standaloneID])
  await store.historySaveTask?.value
  await store.projectSaveTask?.value
  #expect(store.error == nil)
}

@Test func historySeparatesStandaloneChatsFromProjects() {
  let folder = URL(fileURLWithPath: "/Projects/OneCap")
  func conversation(_ date: TimeInterval, workspace: URL? = nil, pinned: Bool = false) -> ChatConversation {
    ChatConversation(
      id: UUID(), messages: [], draft: "Chat", usesAgent: true, workspace: workspace,
      updatedAt: Date(timeIntervalSince1970: date), pinnedAt: pinned ? .now : nil)
  }
  let older = conversation(1)
  let newer = conversation(3)
  let project = conversation(4, workspace: folder)
  let pinned = conversation(2, pinned: true)
  let history = [older, project, pinned, newer]
  #expect(history.historyChats.map(\.id) == [newer.id, older.id])
  #expect(history.historyProjects.flatMap(\.conversations).map(\.id) == [project.id])
  #expect(Set(history.historyChats.map(\.id)).isDisjoint(with:
    history.historyProjects.flatMap(\.conversations).map(\.id)))
  #expect([project].historyChats.isEmpty)
  #expect([older, newer].historyProjects.isEmpty)
}

@Test @MainActor func chatHistoryPersistsSwitchesAndDeletesWithoutLosingSettingsOrDrafts()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-history-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let stateURL = root.appendingPathComponent("state.json")
  let store = AppStore(stateURL: stateURL)
  await store.load()
  let firstID = store.conversationID
  let providerID = UUID()
  let folder = root.appendingPathComponent("Project")
  store.chatUsesAgent = true
  store.selectedAgentID = "agent-a"
  store.selectedProviderID = providerID
  store.workspace = folder
  store.messages = [
    .init(role: "user", text: "  First\n question  "),
    .init(role: "assistant", text: "First answer"),
  ]
  store.draft = "Keep this draft"
  store.resetChat()
  #expect(store.messages.isEmpty)
  #expect(store.conversations.count == 1)
  #expect(store.conversations.first?.title == "First question")
  let firstDate = try #require(store.conversations.first?.updatedAt)
  let secondID = store.conversationID
  store.chatUsesAgent = false
  store.selectedAgentID = "agent-b"
  store.workspace = nil
  store.messages = [
    .init(role: "user", text: "Second question"), .init(role: "assistant", text: "Second answer"),
  ]
  store.openConversation(firstID)
  #expect(store.conversationID == firstID)
  #expect(store.messages.map(\.text) == ["  First\n question  ", "First answer"])
  #expect(store.draft == "Keep this draft")
  #expect(store.chatUsesAgent)
  #expect(store.selectedAgentID == "agent-a")
  #expect(store.selectedProviderID == providerID)
  #expect(store.workspace == folder)
  #expect(store.agentNeedsHistoryContext)
  #expect(store.conversations.first(where: { $0.id == firstID })?.updatedAt == firstDate)
  #expect(store.conversations.historyProjects.first?.folder == folder)
  await store.historySaveTask?.value

  let reopened = AppStore(stateURL: stateURL)
  await reopened.load()
  #expect(reopened.conversations.count == 2)
  reopened.openConversation(firstID)
  #expect(reopened.messages.last?.text == "First answer")
  #expect(reopened.draft == "Keep this draft")
  reopened.deleteConversation(firstID)
  #expect(reopened.messages.isEmpty)
  #expect(reopened.conversations.map(\.id) == [secondID])
  // New empty chats must never create blank rows or resurrect a deleted chat.
  reopened.resetChat()
  reopened.resetChat()
  await reopened.historySaveTask?.value
  let saved = try await ConversationRepository(
    url: root.appendingPathComponent("conversations.json")
  ).load()
  #expect(saved.map(\.id) == [secondID])
  #expect(reopened.error == nil)
}

@Test @MainActor func historySnapshotsFreezeInterruptedRepliesAndAllowNavigationWhileSending()
  async throws
{
  let store = AppStore()
  let timing = ThinkingTime(startedAt: Date.now.addingTimeInterval(-2))
  store.messages = [
    .init(role: "user", text: "Question"),
    .init(role: "assistant", text: "Partial", thinkingTime: timing, replyState: .responding),
    .init(role: "assistant", text: "", thinkingTime: timing, replyState: .thinking),
  ]
  store.checkpointConversation()
  let saved = try #require(store.conversations.first)
  #expect(saved.messages.count == 2)
  #expect(saved.messages.last?.thinkingTime?.isRunning == false)
  #expect(saved.messages.last?.replyState == .stopped)
  #expect(store.messages[1].thinkingTime?.isRunning == true)
  #expect(saved.matches("PARTIAL"))
  #expect(!saved.matches("unrelated"))
  let id = store.conversationID
  store.resetChat()
  let blankID = store.conversationID
  store.sending = true
  store.openConversation(id)
  #expect(store.conversationID == id)
  #expect(store.conversationID != blankID)
  #expect(!store.sending)
  #expect(store.messages.last?.thinkingTime?.isRunning == false)

}

@Test @MainActor func unreadableHistoryIsNotOverwritten() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-history-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("conversations.json")
  let corrupt = Data("invalid history".utf8)
  try corrupt.write(to: url)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  await store.load()
  store.messages = [.init(role: "user", text: "A new chat")]
  store.checkpointConversation()
  await store.historySaveTask?.value
  #expect(try Data(contentsOf: url) == corrupt)
  #expect(store.error?.contains("Could not load chat history") == true)
}

@Test @MainActor func reopenedAgentChatReplaysTranscriptOnceThenUsesLiveSession() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-history-agent-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let script = root.appendingPathComponent("agent.py")
  let source = #"""
    import json, sys
    prompts = 0
    def send(obj):
        print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        if m.get('method') == 'initialize':
            send({'jsonrpc':'2.0','id':m['id'],'result':{'protocolVersion':1}})
        elif m.get('method') == 'session/new':
            send({'jsonrpc':'2.0','id':m['id'],'result':{'sessionId':'restored'}})
        elif m.get('method') == 'session/prompt':
            prompts += 1
            blocks = m['params']['prompt']
            valid = len(blocks) == 2 and 'Prior question' in blocks[0]['text'] and 'Prior answer' in blocks[0]['text'] if prompts == 1 else len(blocks) == 1
            answer = 'Context kept' if valid else 'Context lost or repeated'
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'restored','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':answer}}}})
            send({'jsonrpc':'2.0','id':m['id'],'result':{'stopReason':'end_turn'}})
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  let agent = InstalledAgent(
    id: "history-agent", name: "Test", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  store.installed = [agent]
  store.selectedAgentID = agent.id
  store.chatUsesAgent = true
  store.workspace = root
  store.messages = [
    .init(role: "user", text: "Prior question"), .init(role: "assistant", text: "Prior answer"),
  ]
  let savedID = store.conversationID
  store.resetChat()
  store.openConversation(savedID)
  await store.connect()
  defer { store.resetChat() }
  #expect(store.acp.sessionReady)
  for question in ["Follow up", "Another follow up"] {
    store.send(question, useAgent: true)
    for _ in 0..<300 {
      if !store.sending { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!store.sending)
    #expect(store.messages.last?.text == "Context kept")
    #expect(!store.agentNeedsHistoryContext)
  }
  #expect(store.messages.count == 6)
  #expect(store.error == nil)
}

@Test @MainActor func historyMenuChangesSurviveCheckpointsArchiveAndDiskReload() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-history-menu-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let stateURL = root.appendingPathComponent("state.json")
  let store = AppStore(stateURL: stateURL)
  await store.load()
  store.messages = [.init(role: "user", text: "Original question")]
  store.checkpointConversation()
  let id = store.conversationID
  store.renameConversation(id, title: "  A better\n title  ")
  store.toggleConversationPin(id)
  #expect(store.conversations.first?.title == "A better title")
  #expect(store.conversations.first?.isPinned == true)
  // Completing another response must preserve metadata changed through the menu.
  store.messages.append(.init(role: "assistant", text: "An answer"))
  store.checkpointConversation()
  #expect(store.conversations.first?.title == "A better title")
  #expect(store.conversations.first?.isPinned == true)
  store.renameConversation(id, title: "   ")
  #expect(store.conversations.first?.title == "A better title")
  store.toggleConversationArchive(id)
  #expect(store.conversationID != id)
  #expect(store.messages.isEmpty)
  #expect(store.conversations.first?.isArchived == true)
  await store.historySaveTask?.value

  let reopened = AppStore(stateURL: stateURL)
  await reopened.load()
  #expect(reopened.conversations.first?.title == "A better title")
  #expect(reopened.conversations.first?.isPinned == true)
  #expect(reopened.conversations.first?.isArchived == true)
  reopened.toggleConversationArchive(id)
  reopened.toggleConversationPin(id)
  reopened.openConversation(id)
  #expect(reopened.messages.map(\.text) == ["Original question", "An answer"])
  #expect(reopened.conversations.first?.isArchived == false)
  #expect(reopened.conversations.first?.isPinned == false)
  await reopened.historySaveTask?.value
  #expect(reopened.error == nil)
}
