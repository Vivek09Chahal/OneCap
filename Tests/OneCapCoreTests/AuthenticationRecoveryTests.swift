import Foundation
import Testing

@testable import OneCapCore

@Test func oauthExpiryIsRecognizedWithoutTreatingQuotaOrNetworkFailuresAsLoginFailures() {
    #expect(ACPRequestError(code: -32603,
        message: "Failed to authenticate: OAuth session expired and could not be refreshed").authenticationRequired)
    #expect(ACPRequestError(code: -32000, message: "Sign in").authenticationRequired)
    for message in ["Rate limit exceeded", "Account balance exhausted", "Connection timed out", "Model not available"] {
        #expect(!ACPRequestError(code: -32603, message: message).authenticationRequired)
    }
}

@Test @MainActor func expiredSessionStartsTheAdvertisedTerminalLoginAndVerifiesNewCredentials() async throws {
    let fixture = try ExpiredAuthFixture(expireOnStart: true)
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    var logins = 0
    connection.onTerminalLogin = { command in
        logins += 1
        #expect(command.arguments.suffix(4) == ["--cli", "auth", "login", "--claudeai"])
        try Data().write(to: fixture.credentials)
    }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    try await connection.prepareSession()
    #expect(connection.sessionReady)
    #expect(!connection.authenticationRequired)
    #expect(logins == 1)
}

@Test @MainActor func promptExpiryPreservesChatAndDraftThenExplicitRetryReusesTheUserMessage() async throws {
    let fixture = try ExpiredAuthFixture()
    defer { fixture.cleanup() }
    let store = AppStore(stateURL: fixture.root.appendingPathComponent("state.json"))
    store.installed = [fixture.agent]
    store.selectedAgentID = fixture.agent.id
    store.chatUsesAgent = true
    store.acp.onTerminalLogin = { _ in try Data().write(to: fixture.credentials) }
    await store.connect()
    defer { store.resetChat() }
    let conversation = store.conversationID
    store.draft = "Keep this next message"
    store.send("Do the task", useAgent: true)
    try await waitForAuthRecovery { !store.sending }
    let messageID = try #require(store.messages.first?.id)
    #expect(store.acp.authenticationRequired)
    #expect(!store.acp.sessionReady)
    #expect(store.connectionError?.contains("Sign in again") == true)
    #expect(store.error == nil)
    #expect(store.messages.map(\.text) == ["Do the task"])
    await store.authenticate(try #require(store.acp.authMethods.first))
    #expect(store.acp.sessionReady)
    #expect(store.authenticationNeedsRetry)
    #expect(store.conversationID == conversation)
    #expect(store.draft == "Keep this next message")
    store.retryAuthenticatedMessage()
    try await waitForAuthRecovery { !store.sending }
    #expect(store.messages.first?.id == messageID)
    #expect(store.messages.filter { $0.role == "user" }.count == 1)
    #expect(store.messages.last?.text == "Recovered reply")
    #expect(!store.authenticationNeedsRetry)
    #expect(store.connectionError == nil)
}

@Test @MainActor func unsuccessfulLoginDoesNotStartASecondLoginOrEnableSending() async throws {
    let fixture = try ExpiredAuthFixture(expireOnStart: true)
    defer { fixture.cleanup() }
    let store = AppStore(stateURL: fixture.root.appendingPathComponent("state.json"))
    store.installed = [fixture.agent]
    store.selectedAgentID = fixture.agent.id
    store.chatUsesAgent = true
    var logins = 0
    store.acp.onTerminalLogin = { _ in logins += 1 }
    // Establish methods directly so this test exercises the explicit recovery action.
    try await store.acp.connect(fixture.agent, workspace: fixture.root)
    defer { store.resetChat() }
    await store.authenticate(try #require(store.acp.authMethods.first))
    #expect(logins == 1)
    #expect(!store.acp.sessionReady)
    #expect(store.acp.authenticationRequired)
    #expect(store.connectionError?.contains("could not be restored") == true)
}

@Test @MainActor func cancelledRecoveryKeepsTranscriptAndDraft() async throws {
    let fixture = try ExpiredAuthFixture()
    defer { fixture.cleanup() }
    let store = AppStore(stateURL: fixture.root.appendingPathComponent("state.json"))
    store.installed = [fixture.agent]
    store.selectedAgentID = fixture.agent.id
    store.chatUsesAgent = true
    await store.connect()
    defer { store.resetChat() }
    store.messages = [.init(role: "user", text: "Keep this chat")]
    store.draft = "Keep this draft"
    store.acp.onTerminalLogin = { _ in throw CancellationError() }
    await store.authenticate(try #require(store.acp.authMethods.first))
    #expect(store.messages.first?.text == "Keep this chat")
    #expect(store.draft == "Keep this draft")
    #expect(!store.acp.sessionReady)
    #expect(!store.connecting)
    #expect(store.status.contains("cancelled"))
}

@Test @MainActor func streamedAndStructuredOAuthErrorsExposeInlineRecovery() async throws {
    for style in ["streamed", "structured"] {
        let fixture = try ExpiredAuthFixture(failureStyle: style)
        defer { fixture.cleanup() }
        let store = AppStore(stateURL: fixture.root.appendingPathComponent("state.json"))
        store.installed = [fixture.agent]
        store.selectedAgentID = fixture.agent.id
        store.chatUsesAgent = true
        await store.connect()
        store.send("hi", useAgent: true)
        try await waitForAuthRecovery { !store.sending }
        #expect(store.acp.authenticationRequired)
        #expect(!store.acp.sessionReady)
        #expect(store.connectionError?.contains("Sign in again") == true)
        #expect(store.error == nil)
        #expect(store.messages.first?.text == "hi")
        #expect(!store.acp.authMethods.isEmpty)
        store.resetChat()
    }
}

@Test @MainActor func ordinaryAgentErrorsStayInlineAndSuccessfulQuotedErrorsDoNotTriggerLogin() async throws {
    for style in ["ordinary", "success-quote"] {
        let fixture = try ExpiredAuthFixture(failureStyle: style)
        defer { fixture.cleanup() }
        let store = AppStore(stateURL: fixture.root.appendingPathComponent("state.json"))
        store.installed = [fixture.agent]
        store.selectedAgentID = fixture.agent.id
        store.chatUsesAgent = true
        await store.connect()
        store.send("Explain OAuth", useAgent: true)
        try await waitForAuthRecovery { !store.sending }
        #expect(!store.acp.authenticationRequired)
        #expect(store.acp.sessionReady)
        #expect(store.error == nil)
        if style == "ordinary" { #expect(store.connectionError?.contains("Agent request failed") == true) }
        else { #expect(store.connectionError == nil) }
        store.resetChat()
    }
}

@MainActor private func waitForAuthRecovery(_ condition: () -> Bool) async throws {
    for _ in 0..<300 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw AppFailure("Timed out waiting for authentication recovery")
}

private struct ExpiredAuthFixture {
    let root: URL
    let agent: InstalledAgent
    let credentials: URL
    init(expireOnStart: Bool = false, failureStyle: String = "") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-auth-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        credentials = root.appendingPathComponent("signed-in")
        let script = root.appendingPathComponent("agent.py")
        try #"""
        import json, sys, pathlib
        marker=pathlib.Path(sys.argv[1]).parent/'signed-in'
        expire_on_start='--expired' in sys.argv
        def send(obj): print(json.dumps(dict(jsonrpc='2.0',**obj)),flush=True)
        for line in sys.stdin:
            m=json.loads(line); method=m.get('method'); result={}
            if method=='initialize':
                result=dict(protocolVersion=1,authMethods=[dict(id='claude-ai-login',name='Claude Subscription',type='terminal',args=['--cli','auth','login','--claudeai'])])
            elif method=='session/new':
                if expire_on_start and not marker.exists():
                    send(dict(id=m['id'],error=dict(code=-32603,message='Failed to authenticate: OAuth session expired and could not be refreshed')))
                    continue
                result=dict(sessionId='recovery')
            elif method=='session/prompt':
                if not marker.exists():
                    style = next((a for a in sys.argv if a.startswith('--style=')), '')
                    if style in ['--style=streamed', '--style=ordinary', '--style=success-quote']:
                        text = 'Failed to authenticate: OAuth session expired and could not be refreshed' if style != '--style=ordinary' else 'An explanation of OAuth session expired errors.'
                        send(dict(method='session/update',params=dict(sessionId='recovery',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text=text)))))
                    if style == '--style=success-quote':
                        send(dict(id=m['id'],result=dict(stopReason='end_turn')))
                    elif style == '--style=structured':
                        send(dict(id=m['id'],error=dict(code=-32603,message='Internal error',data=dict(details=dict(message='OAuth session expired and could not be refreshed')))))
                    else:
                        send(dict(id=m['id'],error=dict(code=-32603,message='Internal error' if style else 'Failed to authenticate: OAuth session expired and could not be refreshed')))
                    continue
                send(dict(method='session/update' ,params=dict(sessionId='recovery',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='Recovered reply')))))
                result=dict(stopReason='end_turn')
            send(dict(id=m['id'],result=result))
        """#.write(to: script, atomically: true, encoding: .utf8)
        agent = InstalledAgent(id: "claude-recovery", name: "Claude fixture", version: "1",
            executable: "/usr/bin/python3", arguments: ["-u", script.path, script.path] + (expireOnStart ? ["--expired"] : []) + (failureStyle.isEmpty ? [] : ["--style=\(failureStyle)"]),
            environment: [:], directory: root.path)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
