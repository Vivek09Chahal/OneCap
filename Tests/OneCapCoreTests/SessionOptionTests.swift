import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func composerOptionsChangeTheAgentAndSurviveSessionRestart() async throws {
  let fixture = try SessionOptionFixture()
  defer { fixture.cleanup() }
  let connection = ACPConnection()
  defer { connection.close() }
  try await connection.connect(fixture.agent, workspace: fixture.root)
  try await connection.prepareSession()
  let model = try #require(connection.sessionOptions.first { $0.category == "model" })
  #expect(model.choices.map(\.group) == ["Recommended", "Recommended", "Recommended"])
  try await connection.setSessionOption("model", value: "large")
  #expect(connection.sessionOptions.first?.selectedName == "Large")
  #expect(!connection.updatingConfiguration)
  try await connection.setSessionOption("thought", value: "high")
  try await connection.restartSession()
  #expect(connection.sessionOptions.map(\.currentValue) == ["large", "high"])
  var answer = ""
  connection.onText = { answer += $0 }
  try await connection.prompt("Hello")
  #expect(answer == "large/high")
}

@Test @MainActor func rejectedOptionKeepsTheConfirmedValueAndConversationReady() async throws {
  let fixture = try SessionOptionFixture()
  defer { fixture.cleanup() }
  let connection = ACPConnection()
  defer { connection.close() }
  try await connection.connect(fixture.agent, workspace: fixture.root)
  try await connection.prepareSession()
  await #expect(throws: (any Error).self) {
    try await connection.setSessionOption("model", value: "denied")
  }
  #expect(connection.sessionOptions.first?.currentValue == "small")
  #expect(connection.sessionReady)
  #expect(!connection.updatingConfiguration)
  await #expect(throws: (any Error).self) {
    try await connection.setSessionOption("model", value: "not-advertised")
  }
}

@Test @MainActor func agentConfigurationNotificationsRefreshComposerOptions() async throws {
  let fixture = try SessionOptionFixture()
  defer { fixture.cleanup() }
  let connection = ACPConnection()
  defer { connection.close() }
  try await connection.connect(fixture.agent, workspace: fixture.root)
  try await connection.prepareSession()
  try await connection.prompt("update-options")
  #expect(connection.sessionOptions.first?.currentValue == "large")
  try await connection.prompt("stale-update")
  #expect(connection.sessionOptions.first?.currentValue == "large")
}

@Test @MainActor func legacyAgentModelAndModeSelectorsUseTheirOwnRPCs() async throws {
  let fixture = try SessionOptionFixture(legacy: true)
  defer { fixture.cleanup() }
  let connection = ACPConnection()
  defer { connection.close() }
  try await connection.connect(fixture.agent, workspace: fixture.root)
  try await connection.prepareSession()
  try await connection.setSessionOption("model", value: "large")
  try await connection.setSessionOption("mode", value: "plan")
  #expect(connection.sessionOptions.map(\.currentValue) == ["large", "plan"])
  var answer = ""
  connection.onText = { answer += $0 }
  try await connection.prompt("Hello")
  #expect(answer == "large/plan")
}

@Test @MainActor func choosingWorkingFolderPreservesTheComposedMessage() {
  let store = AppStore(
    stateURL: FileManager.default.temporaryDirectory
      .appendingPathComponent("OneCap-folder-\(UUID()).json"))
  store.draft = "Continue building this app"
  store.selectWorkspace(URL(fileURLWithPath: "/tmp"))
  #expect(store.draft == "Continue building this app")
  #expect(store.workspace?.path == "/tmp")
  store.selectWorkspace(nil)
  #expect(store.draft == "Continue building this app")
  store.selectProvider(UUID())
  #expect(store.draft == "Continue building this app")
  store.resetChat()
  #expect(store.draft.isEmpty)
}

@Test func unsupportedConfigurationTypesDoNotInventControls() {
  let options = ACPSessionOption.decode([
    "configOptions": [
      ["id": "future", "name": "Future", "type": "unknown", "currentValue": "x"],
      ["id": "bool", "name": "Boolean", "type": "boolean", "currentValue": true],
    ]
  ])
  #expect(options.isEmpty)
}

private struct SessionOptionFixture {
  let root: URL
  let agent: InstalledAgent
  init(legacy: Bool = false) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-options-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json, sys
    legacy = '--legacy' in sys.argv
    model, thought, mode, session = 'small', 'low', 'ask', 0
    def options():
        return [dict(id='model', name='Model', category='model', type='select', currentValue=model,
            options=[dict(group='recommended', name='Recommended', options=[dict(value=v,name=n) for v,n in [('small','Small'),('large','Large'),('denied','Denied')]])]),
            dict(id='thought', name='Reasoning', category='thought_level', type='select', currentValue=thought,
            options=[dict(value=v,name=v.title()) for v in ['low','high']])]
    def send(obj): print(json.dumps(dict(jsonrpc='2.0', **obj)), flush=True)
    def update(sid): send(dict(method='session/update', params=dict(sessionId=sid, update=dict(sessionUpdate='config_option_update', configOptions=options()))))
    for line in sys.stdin:
        m=json.loads(line); p=m.get('params',{}); method=m.get('method')
        result={}
        if method=='initialize': result=dict(protocolVersion=1)
        elif method=='session/new':
            session+=1; model,thought,mode='small','low','ask'
            result=dict(sessionId=str(session))
            if legacy:
                result.update(models=dict(currentModelId=model,availableModels=[dict(modelId=v,name=v.title()) for v in ['small','large']]), modes=dict(currentModeId=mode,availableModes=[dict(id=v,name=v.title()) for v in ['ask','plan']]))
            else: result['configOptions']=options()
        elif method=='session/set_config_option':
            assert p['sessionId']==str(session)
            if p['value']=='denied':
                send(dict(id=m['id'],error=dict(code=-32602,message='Model not available for this account')))
                continue
            if p['configId']=='model': model=p['value']
            elif p['configId']=='thought': thought=p['value']
            result=dict(configOptions=options())
        elif method=='session/set_model': model=p['modelId']
        elif method=='session/set_mode': mode=p['modeId']
        elif method=='session/prompt':
            text=p['prompt'][-1]['text']
            if text=='update-options':
                model='large'; update(str(session))
            elif text=='stale-update':
                model='small'; update('old-session')
            send(dict(method='session/update',params=dict(sessionId=str(session),update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text=model+'/'+(mode if legacy else thought))))))
            result=dict(stopReason='end_turn')
        else: raise Exception('Unexpected RPC: '+str(method))
        send(dict(id=m['id'],result=result))
    """#.write(to: script, atomically: true, encoding: .utf8)
    agent = InstalledAgent(
      id: UUID().uuidString, name: "Options fixture", version: "1",
      executable: "/usr/bin/python3",
      arguments: ["-u", script.path] + (legacy ? ["--legacy"] : []),
      environment: [:], directory: root.path)
  }
  func cleanup() { try? FileManager.default.removeItem(at: root) }
}
