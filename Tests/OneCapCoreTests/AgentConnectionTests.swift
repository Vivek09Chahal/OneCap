import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func connectionOpensRequiredBrowserLoginAndBecomesReady() async throws {
  let fixture = try LoginAgentFixture()
  defer { fixture.cleanup() }
  var opened: [URL] = []
  let store = AppStore(
    stateURL: fixture.root.appendingPathComponent("state.json"),
    openLoginURL: {
      opened.append($0)
      return true
    })
  store.installed = [fixture.agent]
  _ = try await store.repository.register(fixture.agent)
  store.chatUsesAgent = true
  store.selectAgent(fixture.agent.id)
  #expect(store.agentConnectionKey?.agentID == fixture.agent.id)
  await store.connect()  // The same operation invoked by ChatView's selection-keyed task.
  defer { store.resetChat() }
  #expect(store.connectionError == nil)
  #expect(store.error == nil)
  #expect(store.acp.sessionReady)
  #expect(opened.map(\.absoluteString) == ["https://example.com/oauth/authorize?state=fixture"])
  store.send("Hello", useAgent: true)
  try await waitForConnection { !store.sending }
  #expect(store.messages.last?.text == "Authenticated chat")
}

@Test @MainActor func connectionReusesExistingLoginWithoutOpeningBrowser() async throws {
  let fixture = try LoginAgentFixture(flags: ["--signed-in"])
  defer { fixture.cleanup() }
  var opened = false
  let store = AppStore(
    stateURL: fixture.root.appendingPathComponent("state.json"),
    openLoginURL: { _ in
      opened = true
      return true
    })
  store.installed = [fixture.agent]
  store.selectedAgentID = fixture.agent.id
  await store.connect()
  defer { store.resetChat() }
  #expect(store.acp.sessionReady)
  #expect(!opened)
}

@Test @MainActor func openingBrowserAloneDoesNotCompleteAuthentication() async throws {
  let fixture = try LoginAgentFixture(flags: ["--deny-login"])
  defer { fixture.cleanup() }
  var opened = false
  let store = AppStore(
    stateURL: fixture.root.appendingPathComponent("state.json"),
    openLoginURL: { _ in
      opened = true
      return true
    })
  store.installed = [fixture.agent]
  store.selectedAgentID = fixture.agent.id
  await store.connect()
  defer { store.resetChat() }
  #expect(opened)
  #expect(!store.acp.sessionReady)
  #expect(store.connectionError != nil)
}

@Test @MainActor func unrelatedURLRequestCannotOpenBrowser() async throws {
  let fixture = try LoginAgentFixture(flags: ["--invalid-scope"])
  defer { fixture.cleanup() }
  var opened = false
  let store = AppStore(
    stateURL: fixture.root.appendingPathComponent("state.json"),
    openLoginURL: { _ in
      opened = true
      return true
    })
  store.installed = [fixture.agent]
  store.selectedAgentID = fixture.agent.id
  await store.connect()
  defer { store.resetChat() }
  #expect(!opened)
  #expect(!store.acp.sessionReady)
}

@Test @MainActor func switchingAgentsDuringConnectionKeepsTheNewAgentReady() async throws {
  let slow = try LoginAgentFixture(flags: ["--slow-init", "--signed-in"])
  let fast = try LoginAgentFixture(flags: ["--signed-in"])
  defer {
    slow.cleanup()
    fast.cleanup()
  }
  let store = AppStore(stateURL: slow.root.appendingPathComponent("state.json"))
  store.installed = [slow.agent, fast.agent]
  _ = try await store.repository.register(slow.agent)
  _ = try await store.repository.register(fast.agent)
  store.chatUsesAgent = true
  store.selectedAgentID = slow.agent.id
  let old = Task { await store.connect() }
  try await waitForConnection { store.connecting }
  old.cancel()
  store.selectAgent(fast.agent.id)
  await store.connect()
  await old.value
  defer { store.resetChat() }
  #expect(store.selectedAgentID == fast.agent.id)
  #expect(store.acp.sessionReady)
  #expect(!store.connecting)
  #expect(store.connectionError == nil)
}

@Test func browserLoginOnlyAllowsWebAndLoopbackURLs() {
  #expect(LoginURL.validated("https://example.com/login") != nil)
  #expect(LoginURL.validated("http://127.0.0.1:8080/login") != nil)
  for value in [
    "file:///tmp/login", "javascript:alert(1)", "http://example.com/login",
    "https://secret@example.com/login",
  ] {
    #expect(LoginURL.validated(value) == nil)
  }
}

@MainActor private func waitForConnection(_ condition: () -> Bool) async throws {
  for _ in 0..<300 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw AppFailure("Timed out waiting for agent connection.")
}

private struct LoginAgentFixture {
  let root: URL
  let agent: InstalledAgent
  init(flags: [String] = []) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OneCap-login-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("login-agent.py")
    let source = #"""
      import json, sys, time
      logged_in = '--signed-in' in sys.argv
      def send(obj):
          print(json.dumps(obj), flush=True)
      for line in sys.stdin:
          m = json.loads(line)
          method = m.get('method')
          if method == 'initialize':
              if '--slow-init' in sys.argv: time.sleep(0.3)
              send({'jsonrpc':'2.0','id':m['id'],'result':{'protocolVersion':1,'authMethods':[{'id':'browser','name':'Sign in with browser'}]}})
          elif method == 'session/new':
              if not logged_in:
                  send({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32000,'message':'Authentication required'}})
              else:
                  send({'jsonrpc':'2.0','id':m['id'],'result':{'sessionId':'authenticated-session'}})
          elif method == 'authenticate':
              request_id = m['id'] if '--invalid-scope' not in sys.argv else -100
              send({'jsonrpc':'2.0','id':'browser-request','method':'elicitation/create','params':{'mode':'url','requestId':request_id,'elicitationId':'login','message':'Sign in','url':'https://example.com/oauth/authorize?state=fixture'}})
              response = json.loads(sys.stdin.readline())
              if response.get('result',{}).get('action') == 'accept' and '--deny-login' not in sys.argv:
                  logged_in = True
                  send({'jsonrpc':'2.0','id':m['id'],'result':{}})
              else:
                  send({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32000,'message':'Login was not completed'}})
          elif method == 'session/prompt':
              send({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'authenticated-session','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'Authenticated chat'}}}})
              send({'jsonrpc':'2.0','id':m['id'],'result':{'stopReason':'end_turn'}})
      """#
    try source.write(to: script, atomically: true, encoding: .utf8)
    agent = InstalledAgent(
      id: UUID().uuidString, name: "Login test agent", version: "1", executable: "/usr/bin/python3",
      arguments: ["-u", script.path] + flags, environment: [:], directory: root.path)
  }
  func cleanup() { try? FileManager.default.removeItem(at: root) }
}
