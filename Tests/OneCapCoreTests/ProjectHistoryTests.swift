import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func projectFoldersKeepSeparateChatsAndSurviveAnEmptyHistory() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-projects-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let state = root.appendingPathComponent("state.json")
  let first = root.appendingPathComponent("A/App")
  let second = root.appendingPathComponent("B/App")
  let empty = root.appendingPathComponent("Empty")
  let store = AppStore(stateURL: state)
  await store.load()
  store.newProjectChat(in: first)
  let firstID = store.conversationID
  store.messages = [.init(role: "user", text: "First project question")]
  store.draft = "First draft"
  store.newProjectChat(in: second)
  let secondID = store.conversationID
  #expect(store.workspace == second)
  #expect(store.messages.isEmpty)
  store.messages = [.init(role: "user", text: "Second project question")]
  store.openProject(first)
  #expect(store.conversationID == firstID)
  #expect(store.messages.first?.text == "First project question")
  #expect(store.draft == "First draft")
  store.openProject(second)
  #expect(store.conversationID == secondID)
  #expect(store.messages.first?.text == "Second project question")
  store.newProjectChat(in: empty)
  await store.historySaveTask?.value
  await store.projectSaveTask?.value

  let reopened = AppStore(stateURL: state)
  await reopened.load()
  #expect(Set(reopened.projectFolders.map(\.path)) == Set([first.path, second.path, empty.path]))
  let projects = reopened.conversations.historyProjects(in: reopened.projectFolders)
  #expect(projects.count == 3)
  #expect(projects.first(where: { $0.id == first.path })?.conversations.map(\.id) == [firstID])
  #expect(projects.first(where: { $0.id == second.path })?.conversations.map(\.id) == [secondID])
  #expect(projects.first(where: { $0.id == empty.path })?.conversations.isEmpty == true)
  reopened.deleteConversation(firstID)
  #expect(reopened.projectFolders.contains(where: { $0.path == first.path }))
  reopened.openProject(first)
  #expect(reopened.workspace?.path == first.path)
  #expect(reopened.messages.isEmpty)
  #expect(reopened.conversationID != secondID)
  await reopened.historySaveTask?.value
  await reopened.projectSaveTask?.value
}

@Test @MainActor func existingFolderHistoryMigratesIntoPersistentProjects() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-project-migrate-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent("Existing")
  let old = ChatConversation(
    id: UUID(), messages: [.init(role: "user", text: "Legacy chat")],
    draft: "", usesAgent: true, workspace: folder, updatedAt: .now)
  let history = ConversationRepository(url: root.appendingPathComponent("conversations.json"))
  try await history.save([old])
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  await store.load()
  #expect(store.projectFolders.map(\.path) == [folder.path])
  store.sending = true
  store.newProjectChat(in: root.appendingPathComponent("Blocked"))
  store.openProject(folder)
  #expect(store.workspace == nil)
  #expect(store.projectFolders.count == 1)
  store.sending = false
  await store.historySaveTask?.value
  await store.projectSaveTask?.value
  #expect(
    try await ProjectRepository(url: root.appendingPathComponent("projects.json")).load().map(
      \.path) == [folder.path])
}

@Test func directoryGroupingUsesFullPathsAndSortsEachProjectsOwnHistory() {
  let folder = URL(fileURLWithPath: "/Projects/OneCap")
  let older = ChatConversation(
    id: UUID(), messages: [], draft: "Older", usesAgent: true,
    workspace: folder, updatedAt: Date(timeIntervalSince1970: 10))
  var recent = older
  recent.updatedAt = Date(timeIntervalSince1970: 20)
  recent.draft = "Recent"
  let projects = [older, recent].historyProjects(in: [
    folder, URL(fileURLWithPath: "/Projects/./OneCap"),
  ])
  #expect(projects.count == 1)
  #expect(projects.first?.conversations.map(\.draft) == ["Recent", "Older"])
}
