import Foundation
import Observation
import Synchronization
import Testing

@testable import OneCapCore

@Test @MainActor func repeatedAgentStatusDoesNotInvalidateObservers() throws {
    let store = AppStore(stateURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("OneCap-ui-\(UUID()).json"))
    store.acp.onStatus?("Ready")
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.status
    } onChange: {
        changed.withLock { $0 = true }
    }
    store.acp.onStatus?("Ready")
    #expect(!changed.withLock { $0 })
    store.acp.onStatus?("Working")
    #expect(changed.withLock { $0 })
    #expect(store.status == "Working")
}

@Test @MainActor func streamingPreservesFirstResponseTimingAndIgnoresEmptyOrStoppedChunks() throws {
    let store = AppStore(stateURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("OneCap-ui-\(UUID()).json"))
    let reply = ChatMessage(role: "assistant", text: "", thinkingTime: ThinkingTime(), replyState: .thinking)
    store.messages = [reply]
    store.replyID = reply.id
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.messages
    } onChange: {
        changed.withLock { $0 = true }
    }
    store.acp.onText?("")
    #expect(!changed.withLock { $0 })
    store.acp.onText?("First")
    #expect(changed.withLock { $0 })
    let stoppedAt = try #require(store.messages.first?.thinkingTime?.stoppedAt)
    store.acp.onText?(" second")
    #expect(store.messages.first?.text == "First second")
    #expect(store.messages.first?.replyState == .responding)
    #expect(store.messages.first?.thinkingTime?.stoppedAt == stoppedAt)
    store.stoppingReply = true
    store.acp.onText?(" ignored")
    #expect(store.messages.first?.text == "First second")
}

@Test @MainActor func skillReadinessNotifiesTheUIEvenWhenNoSkillsAreSaved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-skill-ui-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.skillsLoaded
    } onChange: { changed.withLock { $0 = true } }
    try await store.loadSkills()
    #expect(changed.withLock { $0 })
    #expect(store.skillsLoaded)
    #expect(store.skills.isEmpty)
}
