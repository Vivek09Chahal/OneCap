import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func codexUsesNativeProtocolAndWaitsForTurnCompletion() async throws {
    let fixture = try CodexServerFixture(flags: ["--early-completion", "--pages"])
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    var output = ""
    var sawCommand = false
    connection.onText = {
        output += $0
        if connection.activityPhase == "Running command in terminal" { sawCommand = true }
    }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    try await connection.prepareSession()
    #expect(connection.sessionReady)
    #expect(connection.sessionOptions.first(where: \.isModelSelector)?.choices.count == 2)
    try await connection.setSessionOption("model", value: "native-large")
    #expect(connection.sessionOptions.first(where: { $0.id == "reasoning_effort" })?.currentValue == "high")
    try await connection.prompt("Hello", attachments: [.init(name: "notes.txt", text: "Reference")])
    #expect(output == "Hello from official Codex")
    #expect(sawCommand)
    #expect(connection.toolActivities.isEmpty)
    let messages = try fixture.requests()
    let methods = messages.compactMap { $0["method"] as? String }
    #expect(methods.contains("initialized"))
    #expect(methods.contains("thread/start"))
    #expect(methods.contains("turn/start"))
    #expect(!methods.contains(where: { $0.hasPrefix("session/") || $0 == "authenticate" }))
    #expect(messages.allSatisfy { $0["jsonrpc"] == nil })
    let turn = messages.first { $0["method"] as? String == "turn/start" }?["params"] as? [String: Any]
    #expect(turn?["model"] as? String == "native-large")
    #expect(turn?["effort"] as? String == "high")
    #expect((turn?["input"] as? [[String: String]])?.contains { $0["text"]?.contains("Reference") == true } == true)
}

@Test @MainActor func codexReusesSignInAndConfirmsBrowserLogin() async throws {
    for flags in [[], ["--needs-login"]] {
        let fixture = try CodexServerFixture(flags: flags)
        defer { fixture.cleanup() }
        let connection = ACPConnection()
        defer { connection.close() }
        var opened = 0
        connection.onOpenLoginURL = { _ in opened += 1; return true }
        try await connection.connect(fixture.agent, workspace: fixture.root)
        try await connection.prepareSession()
        #expect(connection.sessionReady)
        #expect(opened == (flags.isEmpty ? 0 : 1))
        #expect(!connection.authenticationRequired)
    }
}

@Test @MainActor func codexDoesNotTreatOpeningBrowserAsSuccessfulLogin() async throws {
    let fixture = try CodexServerFixture(flags: ["--needs-login", "--deny-login"])
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    connection.onOpenLoginURL = { _ in true }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    do { try await connection.prepareSession(); Issue.record("Denied login became ready") }
    catch { #expect(!connection.sessionReady) }
}

@Test @MainActor func codexRoutesApprovalsToTheExistingPermissionUI() async throws {
    let fixture = try CodexServerFixture(flags: ["--approval"])
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    try await connection.prepareSession()
    let prompt = Task { try await connection.prompt("Run a command") }
    try await waitForCodex { connection.permission != nil }
    #expect(connection.permission?.title.contains("echo hello") == true)
    #expect(connection.permission?.options.map(\.id) == ["accept", "decline"])
    connection.resolvePermission("accept")
    try await prompt.value
    #expect(connection.permission == nil)
    let response = try fixture.requests().first { $0["id"] as? String == "approval-1" }
    #expect((response?["result"] as? [String: String])?["decision"] == "accept")
}

@Test @MainActor func codexInterruptsWithoutDisconnectingTheHarness() async throws {
    let fixture = try CodexServerFixture(flags: ["--wait"])
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    try await connection.prepareSession()
    var output = ""
    connection.onText = { output += $0 }
    let prompt = Task { try await connection.prompt("Work") }
    try await waitForCodex { !output.isEmpty }
    connection.cancelPrompt()
    do { try await prompt.value; Issue.record("Interrupted turn returned success") }
    catch { #expect(error is CancellationError) }
    #expect(connection.connected)
    #expect(connection.sessionReady)
    #expect(try fixture.requests().contains { $0["method"] as? String == "turn/interrupt" })
}

@Test @MainActor func codexServerErrorsDoNotIncorrectlyExpireAuthentication() async throws {
    let fixture = try CodexServerFixture(flags: ["--rpc-error"])
    defer { fixture.cleanup() }
    let connection = ACPConnection()
    defer { connection.close() }
    try await connection.connect(fixture.agent, workspace: fixture.root)
    try await connection.prepareSession()
    do { try await connection.prompt("Hello"); Issue.record("Failed request returned success") }
    catch { #expect(!ACPAuthenticationFailure.isRequired(error)) }
    #expect(!connection.authenticationRequired)
    #expect(connection.sessionReady)
}

@Test func codexCatalogInstallsTheOfficialPackageAndPreservesTheAgentID() {
    let entry = Agent(id: "codex-acp", name: "Codex", version: "2.2.2", description: "Adapter",
                      repository: nil, website: nil, license: nil,
                      distribution: .init(binary: nil, npx: nil, uvx: nil))
    let official = OfficialCodex.catalogAgent(replacing: entry)
    #expect(official.id == entry.id)
    #expect(official.repository == "https://github.com/openai/codex")
    #expect(official.distribution.npx?.package == "@openai/codex@\(OfficialCodex.version)")
    #expect(official.distribution.npx?.args == ["app-server"])
}

@Test func harnessCatalogKeepsOtherAgentDistributionsUnchanged() async throws {
    let codex = Agent(id: "codex-acp", name: "Codex", version: "2.2.2", description: "Adapter",
                      repository: nil, website: nil, license: nil,
                      distribution: .init(binary: nil, npx: nil, uvx: nil))
    let other = Agent(id: "future-harness", name: "Future Harness", version: "3", description: "Official ACP interface",
                      repository: "https://example.com/harness", website: nil, license: "MIT",
                      distribution: .init(binary: nil, npx: .init(package: "harness@3", args: ["--acp"], env: nil), uvx: nil))
    let registry = Registry(version: "1", agents: [codex, other])
    let downloader = HarnessCatalogDownload(payload: try JSONEncoder().encode(registry))
    let resolved = try await AgentInstaller(downloader: downloader).catalog()
    #expect(resolved.agents.map(\.id) == [codex.id, other.id])
    #expect(resolved.agents.first?.distribution.npx?.package == "@openai/codex@\(OfficialCodex.version)")
    #expect(resolved.agents.last?.distribution.npx?.package == "harness@3")
    #expect(resolved.agents.last?.distribution.npx?.args == ["--acp"])
    #expect(resolved.agents.last?.version == other.version)
}

@Test @MainActor func codexMigratesExistingAdapterInstallationPreservingAgentSelection() async throws {
    let fixture = try CodexServerFixture()
    defer { fixture.cleanup() }
    let package = fixture.root.appendingPathComponent("node_modules/@openai/codex")
    try FileManager.default.createDirectory(at: package.appendingPathComponent("bin"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: package.appendingPathComponent("bin/codex.js"))
    try Data(#"{"name":"@openai/codex","version":"0.160.1"}"#.utf8)
        .write(to: package.appendingPathComponent("package.json"))
    let old = InstalledAgent(id: "codex-acp", name: "Codex", version: "2.2.2", executable: "/usr/bin/node",
                             arguments: [fixture.root.appendingPathComponent("node_modules/@agentclientprotocol/codex-acp/dist/index.js").path],
                             environment: [:], directory: fixture.root.path)
    let stateURL = fixture.root.appendingPathComponent("state.json")
    let repository = AppRepository(url: stateURL)
    _ = try await repository.register(old)
    let store = AppStore(stateURL: stateURL)
    await store.load()
    let migrated = try #require(store.installed.first)
    #expect(migrated.id == old.id)
    #expect(migrated.version == "0.160.1")
    #expect(migrated.arguments == [package.appendingPathComponent("bin/codex.js").path, "app-server"])
    #expect(store.selectedAgentID == old.id)
    #expect(try await AppRepository(url: stateURL).load().installed.first?.arguments == migrated.arguments)
}

@MainActor private func waitForCodex(_ condition: () -> Bool) async throws {
    for _ in 0..<300 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw AppFailure("Timed out waiting for Codex fixture.")
}

private struct CodexServerFixture {
    let root: URL
    let agent: InstalledAgent
    init(flags: [String] = []) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-codex-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("app-server.py")
        let source = #"""
        import json, sys
        logged_in = '--needs-login' not in sys.argv
        thread = None
        turn = None
        count = 0
        def send(m): print(json.dumps(m), flush=True)
        def reply(m, result): send({'id':m['id'], 'result':result})
        def event(method, params): send({'method':method, 'params':params})
        def model(name, effort):
            return {'id':name,'model':name,'displayName':name,'hidden':False,'isDefault':name=='native-small',
                    'defaultReasoningEffort':effort,'supportedReasoningEfforts':[{'reasoningEffort':effort,'description':'Fixture effort'}]}
        def complete():
            message = {'id':'message-1','type':'agentMessage','text':'Hello from official Codex'}
            event('item/agentMessage/delta', {'threadId':thread,'turnId':turn,'itemId':'message-1','delta':'Hello '})
            event('item/agentMessage/delta', {'threadId':thread,'turnId':turn,'itemId':'message-1','delta':'from official Codex'})
            event('item/completed', {'threadId':thread,'turnId':turn,'item':message})
            event('item/completed', {'threadId':thread,'turnId':turn,'item':{'id':'command-1','type':'commandExecution','command':'echo hello'}})
            event('turn/completed', {'threadId':thread,'turn':{'id':turn,'status':'completed','items':[message]}})
        for line in sys.stdin:
            m = json.loads(line)
            with open('requests.jsonl','a') as log: log.write(json.dumps(m)+'\n')
            method = m.get('method')
            p = m.get('params',{})
            if method == 'initialize': reply(m, {'userAgent':'Codex fixture'})
            elif method == 'account/read': reply(m, {'account':{'type':'chatgpt'} if logged_in else None,'requiresOpenaiAuth':True})
            elif method == 'account/login/start':
                success = '--deny-login' not in sys.argv
                logged_in = success
                event('account/login/completed', {'loginId':'login-1','success':success,'error':None if success else 'Login denied'})
                reply(m, {'type':'chatgpt','loginId':'login-1','authUrl':'https://example.com/codex-login'})
            elif method == 'model/list':
                if '--pages' in sys.argv:
                    reply(m, {'data':[model('native-large','high')] if p.get('cursor') else [model('native-small','medium')],
                              'nextCursor':None if p.get('cursor') else 'page-2'})
                else: reply(m, {'data':[model('native-small','medium'),model('native-large','high')],'nextCursor':None})
            elif method == 'thread/start':
                count += 1
                thread = 'thread-'+str(count)
                reply(m, {'thread':{'id':thread},'model':p.get('model','native-small'),'reasoningEffort':'medium'})
            elif method == 'turn/start':
                if '--rpc-error' in sys.argv:
                    send({'id':m['id'],'error':{'code':-32000,'message':'Selected model is unavailable'}})
                    continue
                turn = 'turn-'+str(count)
                event('item/agentMessage/delta', {'threadId':thread,'turnId':'old-turn','itemId':'stale','delta':'STALE TURN MUST NOT APPEAR'})
                event('turn/started', {'threadId':thread,'turn':{'id':turn,'status':'inProgress'}})
                event('item/started', {'threadId':thread,'turnId':turn,'item':{'id':'command-1','type':'commandExecution','command':'echo hello'}})
                event('item/agentMessage/delta', {'threadId':'stale-thread','turnId':turn,'itemId':'stale','delta':'MUST NOT APPEAR'})
                if '--early-completion' in sys.argv:
                    complete()
                    reply(m, {'turn':{'id':turn,'status':'inProgress'}})
                else:
                    reply(m, {'turn':{'id':turn,'status':'inProgress'}})
                    if '--approval' in sys.argv:
                        send({'id':'approval-1','method':'item/commandExecution/requestApproval','params':{
                            'threadId':thread,'turnId':turn,'itemId':'command-1','command':'echo hello','availableDecisions':['accept','decline','cancel']}})
                    elif '--wait' in sys.argv:
                        event('item/agentMessage/delta', {'threadId':thread,'turnId':turn,'itemId':'message-1','delta':'Working'})
                    else: complete()
            elif method == 'turn/interrupt':
                reply(m,{})
                event('turn/completed', {'threadId':thread,'turn':{'id':turn,'status':'interrupted','items':[]}})
            elif m.get('id') == 'approval-1': complete()
            elif method and method != 'initialized':
                send({'id':m.get('id'),'error':{'code':-32601,'message':'Unsupported method: '+method}})
        """#
        try source.write(to: script, atomically: true, encoding: .utf8)
        agent = InstalledAgent(id: "codex", name: "Codex fixture", version: "1", executable: "/usr/bin/python3",
                               arguments: ["-u", script.path] + flags, environment: [:], directory: root.path)
    }
    func requests() throws -> [[String: Any]] {
        try String(contentsOf: root.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            .split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
            }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private struct HarnessCatalogDownload: Downloading {
    let payload: Data
    func data(_ url: URL) async throws -> Data { payload }
}
