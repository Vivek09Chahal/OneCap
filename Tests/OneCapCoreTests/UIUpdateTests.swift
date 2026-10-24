import Foundation
import Observation
import Synchronization
import Testing

@testable import OneCapCore

@Test @MainActor func unchangedBindingsDoNotInvalidateChatObservers() {
    let store = AppStore(stateURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("OneCap-ui-\(UUID()).json"))
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.draft
        _ = store.status
        _ = store.sending
        _ = store.workspace
        _ = store.reviewedFilePath
    } onChange: { changed.withLock { $0 = true } }
    store.draft = ""
    store.status = store.status
    store.sending = false
    store.workspace = nil
    store.reviewedFilePath = nil
    #expect(!changed.withLock { $0 })
    store.draft = "Changed draft"
    #expect(changed.withLock { $0 })
}

@Test @MainActor func unchangedCheckpointAndRenameDoNotPublishOrSaveHistory() async {
    let history = UIHistoryRepository()
    let store = AppStore(stateURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("OneCap-ui-\(UUID()).json"), conversationRepository: history)
    store.historyLoaded = true
    store.messages = [.init(role: "user", text: "Keep this message")]
    store.checkpointConversation(touch: false)
    store.renameConversation(store.conversationID, title: "Saved title")
    await store.historySaveTask?.value
    let writes = await history.writes
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.conversations
    } onChange: { changed.withLock { $0 = true } }
    store.checkpointConversation(touch: false)
    store.renameConversation(store.conversationID, title: "  Saved   title  ")
    await store.historySaveTask?.value
    #expect(!changed.withLock { $0 })
    #expect(await history.writes == writes)
    store.draft = "New content"
    store.checkpointConversation(touch: false)
    await store.historySaveTask?.value
    #expect(changed.withLock { $0 })
    #expect(await history.writes == writes + 1)
    #expect(store.conversations.first?.draft == "New content")
}

private actor UIHistoryRepository: SnapshotRepository {
    private(set) var writes = 0
    func load() -> [ChatConversation] { [] }
    func save(_ value: [ChatConversation]) { writes += 1 }
}

@Test @MainActor func additionalWindowsReuseCatalogAndExplicitRefreshUpdatesMetadata() async {
    let installer = UICatalogInstaller()
    let store = AppStore(installer: installer)
    await store.loadCatalog()
    #expect(await installer.requests == 1)
    let changed = Mutex(false)
    withObservationTracking {
        _ = store.agents
    } onChange: { changed.withLock { $0 = true } }
    await store.loadCatalog()
    #expect(await installer.requests == 1)
    await store.refresh()
    #expect(await installer.requests == 2)
    #expect(!changed.withLock { $0 })
    await installer.setVersion("2")
    await store.refresh()
    #expect(changed.withLock { $0 })
    #expect(store.agents.first?.version == "2")
}

private actor UICatalogInstaller: AgentInstalling {
    private(set) var requests = 0
    private var version = "1"
    func setVersion(_ value: String) { version = value }
    func catalog() -> Registry {
        requests += 1
        return Registry(version: version, agents: [Agent(id: "fixture", name: "Fixture", version: version,
            description: "Fixture", repository: nil, website: nil, license: nil,
            distribution: .init(binary: nil, npx: nil, uvx: nil))])
    }
    func install(_ agent: Agent) throws -> InstalledAgent { throw AppFailure("Unused") }
    func uninstall(_ agent: InstalledAgent, repository: AppRepository) throws -> AgentUninstallResult {
        throw AppFailure("Unused")
    }
}

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
