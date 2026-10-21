import Foundation
import Testing

@testable import OneCapCore

private actor TitleProvider: ProviderResponding {
    var calls: [[ChatMessage]] = []
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func reply(provider: Provider, key: String, messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        try await Task.sleep(for: .milliseconds(10))
        if fails { throw AppFailure("Synthetic title failure") }
        return "\"Build a binary search tree\""
    }
}

@Test @MainActor func generatedProviderTitlesPersistWithoutChangingTheTranscriptOrManualNames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-titles-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let client = TitleProvider()
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"), providerClient: client)
    store.historyLoaded = true
    store.messages = [.init(role: "user", text: "Please implement a binary search tree"),
        .init(role: "assistant", text: "Implemented with insert and search.", replyState: .completed)]
    store.checkpointConversation()
    let id = store.conversationID
    let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
    for _ in 0..<2 { store.generateConversationTitle(id, provider: provider, key: "synthetic") }
    await store.titleTasks[id]?.value
    #expect(store.conversations.first?.title == "Build a binary search tree")
    let calls = await client.calls
    #expect(calls.count == 1 && calls[0].map(\.role) == ["system", "user"])
    #expect(calls[0][1].text.contains("Please implement a binary search tree"))
    #expect(store.messages.count == 2 && store.messages[1].text == "Implemented with insert and search.")
    store.checkpointConversation()
    await store.historySaveTask?.value
    let saved = try await ConversationRepository(url: root.appendingPathComponent("conversations.json")).load()
    #expect(saved.first?.generatedTitle == "Build a binary search tree")
    store.renameConversation(id, title: "My DSA project")
    store.applyGeneratedTitle("A different title", to: id)
    #expect(store.conversations.first?.title == "My DSA project")
}

@Test @MainActor func titleFailuresAndLateResponsesKeepFallbacksAndManualRenames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-titles-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
    for fails in [true, false] {
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"), providerClient: TitleProvider(fails: fails))
        store.messages = [.init(role: "user", text: "Original question"),
            .init(role: "assistant", text: "Answer", replyState: .completed)]
        store.checkpointConversation()
        let id = store.conversationID
        store.generateConversationTitle(id, provider: provider, key: "synthetic")
        if !fails { store.renameConversation(id, title: "Manual title") }
        await store.titleTasks[id]?.value
        #expect(store.conversations.first?.title == (fails ? "Original question" : "Manual title"))
        #expect(store.error == nil)
        store.messages.append(.init(role: "user", text: "Follow up"))
        store.checkpointConversation()
        store.generateConversationTitle(id, provider: provider, key: "synthetic")
        #expect(store.titleTasks[id] == nil)
    }
}

@Test @MainActor func nativeAgentTitlesIgnoreToolTitlesAndStaleSessions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-title-agent-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json, sys
    def send(value): print(json.dumps(value), flush=True)
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); result={}
        if method=='initialize': result={'protocolVersion':1}
        elif method=='session/new': result={'sessionId':'active'}
        elif method=='session/prompt':
            for session, kind, title in [('old','session_info_update','Stale title'),('active','tool_call','Reading files'),('active','session_info_update','Build a binary search tree')]:
                send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':session,'update':{'sessionUpdate':kind,'title':title}}})
            send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'active','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Implemented'}}}})
            result={'stopReason':'end_turn'}
        send({'jsonrpc':'2.0','id':m['id'],'result':result})
    """#.write(to: script, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    let agent = InstalledAgent(id: "test", name: "Test", version: "1", executable: "/usr/bin/python3",
        arguments: ["-u", script.path], environment: [:], directory: root.path)
    store.installed = [agent]
    store.selectedAgentID = agent.id
    store.workspace = root
    await store.connect()
    defer { store.resetChat() }
    store.send("Please implement a binary search tree", useAgent: true)
    await store.sendTask?.value
    #expect(store.conversations.first?.title == "Build a binary search tree")
    #expect(store.messages.map(\.text) == ["Please implement a binary search tree", "Implemented"])
    #expect(store.titleTasks.isEmpty)
}
