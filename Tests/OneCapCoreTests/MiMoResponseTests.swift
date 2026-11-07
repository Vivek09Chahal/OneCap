import Foundation
import Testing

@testable import OneCapCore

@MainActor private func waitForMiMo(_ condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "MiMo fixture did not reach the expected state")
}

@Test(arguments: ["text", "thought", "idle"])
@MainActor func mimoLateTextStaysWithItsReplyAndPersists(_ initial: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-mimo-response-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json,sys,pathlib,time,threading
    root=pathlib.Path(sys.argv[1]); initial=sys.argv[2]; lock=threading.Lock()
    def send(o):
        with lock: print(json.dumps(dict(jsonrpc='2.0',**o)),flush=True)
    def chunk(mid,text,kind='agent_message_chunk'):
        send(dict(method='session/update',params=dict(sessionId='mimo',update=dict(sessionUpdate=kind,messageId=mid,content=dict(type='text',text=text)))))
    def late_idle():
        while not (root/'release').exists(): time.sleep(.01)
        chunk('message-1','Recovered')
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); result={}
        if method=='initialize': result=dict(protocolVersion=1)
        elif method=='session/new': result=dict(sessionId='mimo')
        elif method=='session/prompt':
            text=m['params']['prompt'][-1]['text']
            if text=='first':
                if initial=='text': chunk('message-1','First')
                elif initial=='thought': chunk('message-1','Thinking','agent_thought_chunk')
                # Hold completion until the second user message has been queued.
                while not (root/'complete').exists(): time.sleep(.01)
                send(dict(id=m['id'],result=dict(stopReason='end_turn')))
                if initial=='idle': threading.Thread(target=late_idle,daemon=True).start()
            else:
                chunk('message-2','Second')
                # Old text arrives while the second reply is active.
                chunk('message-1',' suffix')
                send(dict(id=m['id'],result=dict(stopReason='end_turn')))
            continue
        send(dict(id=m['id'],result=result))
    """#.write(to: script, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    defer { store.closeChatSessions(); try? FileManager.default.removeItem(at: root) }
    let agent = InstalledAgent(id: "mimocode", name: "MiMo", version: "fixture", executable: "/usr/bin/python3",
        arguments: ["-u", script.path, root.path, initial], environment: [:], directory: root.path)
    store.installed = [agent]
    store.selectedAgentID = agent.id
    store.chatUsesAgent = true
    store.workspace = root
    await store.connect()
    try #require(store.acp.sessionReady)
    try #require(store.send("first", useAgent: true))
    try await waitForMiMo { store.messages.last?.text == "First" || store.messages.last?.thoughtText == "Thinking" || initial == "idle" }
    let firstID = try #require(store.replyID)
    if initial != "idle" { try #require(store.send("second", useAgent: true)) }
    try Data().write(to: root.appendingPathComponent("complete"))
    try await waitForMiMo { !store.sending }
    if initial == "idle" {
        #expect(store.messages.last?.text == "The agent completed without a text response.")
        try Data().write(to: root.appendingPathComponent("release"))
        try await waitForMiMo { store.messages.last?.text == "Recovered" }
        try #require(store.send("second", useAgent: true))
        try await waitForMiMo { !store.sending }
    }
    let expected = initial == "text" ? "First suffix" : initial == "thought" ? " suffix" : "Recovered suffix"
    #expect(store.messages.first { $0.id == firstID }?.text == expected)
    #expect(store.messages.first { $0.id == firstID }?.replyState == .completed)
    #expect(store.messages.last?.text == "Second")
    #expect(store.messages.last?.replyState == .completed)
    await store.historySaveTask?.value
    let restored = try await store.conversationRepository.load()
    #expect(restored.first { $0.id == store.conversationID }?.messages.first { $0.id == firstID }?.text == expected)
}

@Test @MainActor func mimoLateTextDoesNotReviveStoppedOrFailedReplies() {
    let store = AppStore(stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID()).json"))
    for state in [ReplyState.stopped, .failed] {
        let reply = ChatMessage(role: "assistant", text: "Partial", replyState: state)
        store.messages = [reply]
        store.acp.onReplyText?(reply.id, " late")
        #expect(store.messages == [reply])
    }
}
