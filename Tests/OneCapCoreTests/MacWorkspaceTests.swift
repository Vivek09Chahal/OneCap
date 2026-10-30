import Foundation
import Testing
@testable import OneCapCore

@Test func historyDateGroupsRespectCalendarDaysAcrossDaylightSaving() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
    let start = calendar.startOfDay(for: now)
    let offsets = [0, -1, -2, -7, -8, -30, -31]
    let chats = offsets.map { offset in
        ChatConversation(id: UUID(), messages: [], draft: "Day \(offset)", usesAgent: false,
                         updatedAt: calendar.date(byAdding: .day, value: offset, to: start)!)
    }
    let groups = Array(chats.reversed()).historyDateGroups(now: now, calendar: calendar)
    #expect(groups.map(\.title) == ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Older"])
    #expect(groups.map { $0.conversations.count } == [1, 1, 2, 2, 1])
    #expect(groups.flatMap(\.conversations).map(\.id) == chats.map(\.id))
    #expect([ChatConversation]().historyDateGroups(now: now, calendar: calendar).isEmpty)
}

@Test @MainActor func windowsKeepIndependentDraftsAndShareOrderedHistoryWrites() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-windows-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await first.load()
    let second = first.makeWindowStore()
    let firstID = first.conversationID
    let secondID = second.conversationID
    #expect(firstID != secondID)
    first.draft = "First window"
    second.draft = "Second window"
    first.checkpointConversation()
    second.checkpointConversation()
    first.renameConversation(secondID, title: "Renamed from first window")
    #expect(first.conversationID == firstID)
    #expect(second.conversationID == secondID)
    #expect(first.draft == "First window")
    #expect(second.draft == "Second window")
    #expect(second.conversations.first(where: { $0.id == secondID })?.title == "Renamed from first window")
    await second.historySaveTask?.value
    let restored = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await restored.load()
    #expect(Set(restored.conversations.map(\.id)) == Set([firstID, secondID]))
    #expect(restored.conversations.first(where: { $0.id == secondID })?.title == "Renamed from first window")
    #expect(first.repository === second.repository)
}

@Test @MainActor func deletingAndArchivingChatsResetOtherWindowsBeforeSaving() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-window-delete-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await first.load()
    let second = first.makeWindowStore()
    second.draft = "Delete this draft"
    let deletedID = second.conversationID
    second.checkpointConversation()
    first.deleteConversation(deletedID)
    #expect(second.conversationID != deletedID)
    second.checkpointConversation()
    #expect(!first.conversations.contains { $0.id == deletedID })
    second.draft = "Archive this draft"
    let archivedID = second.conversationID
    second.checkpointConversation()
    first.toggleConversationArchive(archivedID)
    #expect(second.conversationID != archivedID)
    #expect(second.conversations.first(where: { $0.id == archivedID })?.isArchived == true)
    await first.historySaveTask?.value
}
