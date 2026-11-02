import Foundation
import Testing
@testable import OneCapCore

@Test func slashQueriesRespectCaretAndOrdinaryPaths() throws {
    #expect(ComposerSlashQuery.active(in: "/")?.command == "")
    #expect(ComposerSlashQuery.active(in: "/mo")?.argument == nil)
    #expect(ComposerSlashQuery.active(in: "/MODEL gpt 5")?.command == "model")
    #expect(ComposerSlashQuery.active(in: "/model ")?.argument == "")
    #expect(ComposerSlashQuery.active(in: "/skill caveman")?.argument == "caveman")
    #expect(ComposerSlashQuery.active(in: "Use /model here")?.argument == "here")
    #expect(ComposerSlashQuery.active(in: "/tmp/file.txt") == nil)
    #expect(ComposerSlashQuery.active(in: "https://example.com") == nil)
    let draft = "/model gpt\nExplain 👋🏽"
    #expect(ComposerSlashQuery.active(in: draft) == nil)
    let query = try #require(ComposerSlashQuery.active(in: draft, at: draft.firstIndex(of: "\n")))
    #expect(draft.replacingCharacters(in: query.range, with: "") == "\nExplain 👋🏽")
}

@Test @MainActor func slashSuggestionsUseAdvertisedModelsAndRespectBusyState() throws {
    let store = AppStore()
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/"))).map(\.title)
        == ["/model", "/skill", "/attach", "/clear"])
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/mo"))).map(\.title) == ["/model"])
    store.chatUsesAgent = true
    store.acp.sessionOptions = [.init(id: "agent-model", name: "Model", category: "model", currentValue: "exact-id",
        choices: [.init(id: "exact-id", name: "Agent Model", group: nil)])]
    store.acp.sessionReady = true
    let query = try #require(ComposerSlashQuery.active(in: "/model agent"))
    let row = try #require(store.slashSuggestions(for: query).first)
    #expect(row.action == .model(option: "agent-model", value: "exact-id"))
    #expect(row.enabled)
    store.sending = true
    #expect(store.slashSuggestions(for: query).first?.enabled == false)
    store.sending = false
    store.chatUsesAgent = false
    store.providers = [.init(name: "NVIDIA", baseURL: "https://example.com/v1", model: "test-model")]
    let providerRows = store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/model nvidia")))
    #expect(providerRows.map(\.title) == ["test-model"])
    #expect(providerRows.first?.action == .provider(store.providers[0].id))
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/model absent"))).isEmpty)
}

@Test @MainActor func slashSkillSelectionAttachesOneMessageWithoutEnablingGlobalSkill() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-slash-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("SKILL.md")
    try "---\nname: Example\ndescription: Test\n---\nFollow these instructions.".write(to: file, atomically: true, encoding: .utf8)
    var shared = SharedSkill(name: "Example", file: file, project: nil)
    shared.enabled = false
    let other = SharedSkill(name: "Other project", file: file, project: root.appendingPathComponent("Other"))
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    store.skills = [shared, other]
    let rows = store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/skill ")))
    #expect(rows.map(\.title) == ["Example"])
    await store.attachSkill(shared.id)
    #expect(store.draftAttachments.count == 1)
    #expect(store.draftAttachments.first?.text.contains("Follow these instructions.") == true)
    #expect(store.skills.first?.enabled == false)
    #expect(!store.importingFiles)
    #expect(store.error == nil)
    await store.historySaveTask?.value
}

@Test @MainActor func clearSlashCommandRunsDirectlyAndRespectsNavigationGuards() throws {
    let store = AppStore()
    for draft in ["/cl", "/clear", "/CLEAR", "/clear "] {
        let query = try #require(ComposerSlashQuery.active(in: draft))
        let row = try #require(store.slashSuggestions(for: query).first)
        #expect(row.action == .clear)
        #expect(row.enabled)
    }
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/clear argument"))).isEmpty)
    store.sending = true
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/clear"))).first?.enabled == true)
    store.applyingFileUndo = true
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/clear"))).first?.enabled == false)
    store.applyingFileUndo = false
    store.savingReviewedFile = true
    #expect(store.slashSuggestions(for: try #require(ComposerSlashQuery.active(in: "/clear "))).first?.enabled == false)
}

@Test func slashCommandsWorkBeforeBetweenAndAfterTextWithoutConsumingSurroundings() throws {
    for (before, after) in [("", "Existing text"), ("Before 👋🏽 ", "after"), ("Existing text ", ""),
                            ("First line\nMore text ", " next line\nKeep this too")] {
        let draft = before + "/attach " + after
        let caret = draft.index(draft.startIndex, offsetBy: before.count + "/attach ".count)
        let query = try #require(ComposerSlashQuery.active(in: draft, at: caret))
        #expect(query.command == "attach" && query.argument == "")
        #expect(draft.replacingCharacters(in: query.range, with: "") == before + after)
    }
    let draft = "Before /after"
    let caret = draft.index(draft.startIndex, offsetBy: "Before /".count)
    let query = try #require(ComposerSlashQuery.active(in: draft, at: caret))
    #expect(query.command.isEmpty)
    #expect(draft.replacingCharacters(in: query.range, with: "/attach ") == "Before /attach after")
    #expect(ComposerSlashQuery.active(in: "Read https://example.com/path") == nil)
    #expect(ComposerSlashQuery.active(in: "Read /tmp/file.txt") == nil)
    #expect(ComposerSlashQuery.active(in: "Read relative/file.txt") == nil)
    #expect(ComposerSlashQuery.active(in: "Explain this\n/skill caveman")?.argument == "caveman")
}
