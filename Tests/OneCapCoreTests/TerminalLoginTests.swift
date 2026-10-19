import Darwin
import Foundation
@preconcurrency import SwiftTerm
import Testing

@testable import OneCapCore

@Test func terminalDescriptorPreservesInvocationAndOverridesEnvironment() throws {
  let root = FileManager.default.temporaryDirectory
  let agent = InstalledAgent(
    id: "test", name: "Test", version: "1", executable: "/bin/echo",
    arguments: ["acp", "argument with spaces"], environment: ["ONECAP_TEST": "base"],
    directory: root.path)
  let method = try #require(
    AuthMethod(json: [
      "id": "login", "name": "Login", "type": "terminal", "args": ["--login"],
      "env": ["ONECAP_TEST": "override"],
    ]))
  let command = try TerminalLoginCommand(agent: agent, method: method, directory: root)
  #expect(command.executable == agent.executable)
  #expect(command.arguments == ["acp", "argument with spaces", "--login"])
  #expect(command.environment["ONECAP_TEST"] == "override")
  #expect(command.directory == root)
  #expect(
    AuthMethod(json: ["id": "bad", "type": "terminal", "command": "/bin/sh", "args": []]) == nil)
}

@Test func legacyTerminalMetadataUsesItsDeclaredProgram() throws {
  let method = try #require(
    AuthMethod(json: [
      "id": "legacy", "name": "Sign in",
      "_meta": [
        "terminal-auth": [
          "command": "/bin/echo", "args": ["login"], "env": ["ONECAP_TEST": "legacy"],
        ]
      ],
    ]))
  #expect(!method.isAgentManaged)
  let root = FileManager.default.temporaryDirectory
  let agent = InstalledAgent(
    id: "test", name: "Test", version: "1", executable: "/usr/bin/false", arguments: ["acp"],
    environment: [:], directory: root.path)
  let command = try TerminalLoginCommand(agent: agent, method: method, directory: root)
  #expect(command.executable == "/bin/echo")
  #expect(command.arguments == ["login"])
}

@Test @MainActor func terminalLoginOnlySucceedsOnZeroExitAndSupportsCancellation() async throws {
  let command = try fixtureCommand()
  let coordinator = TerminalLoginCoordinator(openURL: { _ in true })
  let success = Task { try await coordinator.run(command) }
  try await waitForTerminal { coordinator.session != nil }
  coordinator.session?.complete(exitCode: 0)
  try await success.value
  #expect(coordinator.session == nil)
  let failure = Task { try await coordinator.run(command) }
  try await waitForTerminal { coordinator.session != nil }
  coordinator.session?.complete(exitCode: 1)
  await #expect(throws: AppFailure.self) { try await failure.value }
  let cancelled = Task { try await coordinator.run(command) }
  try await waitForTerminal { coordinator.session != nil }
  var terminated = false
  coordinator.session?.terminateProcess = { terminated = true }
  coordinator.cancel()
  await #expect(throws: CancellationError.self) { try await cancelled.value }
  #expect(terminated)
  #expect(coordinator.session == nil)
}

@Test @MainActor func terminalOutputOpensLoginURLOnceWithoutPersistingOutput() async throws {
  let coordinator = TerminalLoginCoordinator(openURL: { _ in true })
  let task = Task { try await coordinator.run(fixtureCommand()) }
  try await waitForTerminal { coordinator.session != nil }
  let session = try #require(coordinator.session)
  session.consumeOutput(Data("Open https://example.com/lo".utf8))
  #expect(session.loginURL == nil)
  session.consumeOutput(Data("gin in your browser\n".utf8))
  #expect(session.loginURL?.absoluteString == "https://example.com/login")
  coordinator.cancel()
  _ = try? await task.value
}

@Test @MainActor func terminalAuthReconnectsWithoutCallingAuthenticateRPC() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-terminal-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let marker = root.appendingPathComponent("signed-in")
  let script = root.appendingPathComponent("agent.py")
  let source = #"""
    import json, os, sys
    marker = sys.argv[1]
    def send(obj): print(json.dumps(obj), flush=True)
    for line in sys.stdin:
        m = json.loads(line)
        method = m.get('method')
        if method == 'initialize':
            supported = m['params']['clientCapabilities'].get('auth',{}).get('terminal') == True
            send({'jsonrpc':'2.0','id':m['id'],'result':{'protocolVersion':1,'authMethods':[{'id':'login','name':'Terminal login','type':'terminal','args':['--login'],'env':{'ONECAP_LOGIN':'yes'}}] if supported else []}})
        elif method == 'session/new':
            if os.path.exists(marker):
                send({'jsonrpc':'2.0','id':m['id'],'result':{'sessionId':'after-terminal'}})
            else:
                send({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32000,'message':'Authentication required'}})
        elif method == 'authenticate':
            send({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32601,'message':'Terminal auth must not use authenticate'}})
    """#
  try source.write(to: script, atomically: true, encoding: .utf8)
  let agent = InstalledAgent(
    id: "terminal", name: "Terminal", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path, marker.path], environment: [:], directory: root.path)
  let connection = ACPConnection()
  var calls = 0
  connection.onTerminalLogin = { command in
    calls += 1
    #expect(command.executable == agent.executable)
    #expect(command.arguments == agent.arguments + ["--login"])
    #expect(command.environment["ONECAP_LOGIN"] == "yes")
    try Data().write(to: marker)
  }
  try await connection.connect(agent, workspace: root)
  defer { connection.close() }
  try await connection.prepareSession()
  #expect(connection.sessionReady)
  #expect(calls == 1)
}

@Test @MainActor func realPseudoTerminalSupportsInteractiveInputAndTTY() async throws {
  let runner = PTYTestDriver()
  try await runner.run()
  #expect(runner.output.contains("TTY=1"))
  #expect(runner.output.contains("INPUT=approved"))
}

@MainActor private final class PTYTestDriver: @preconcurrency LocalProcessDelegate {
  var output = ""
  private var process: LocalProcess!
  private var completion: CheckedContinuation<Void, Error>?
  private var sent = false
  func run() async throws {
    process = LocalProcess(delegate: self)
    defer { if process.running { process.terminate() } }
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      process.startProcess(
        executable: "/bin/sh",
        args: [
          "-c",
          "test -t 0 && test -t 1 && echo TTY=1; echo READY; read answer; echo INPUT=$answer; sleep 0.1",
        ], currentDirectory: "/tmp")
      if !process.running {
        completion = nil
        continuation.resume(throwing: AppFailure("PTY launch failed"))
      }
    }
  }
  func dataReceived(slice: ArraySlice<UInt8>) {
    output += String(decoding: slice, as: UTF8.self)
    if output.contains("READY"), !sent {
      sent = true
      process.send(data: Array("approved\n".utf8)[...])
    }
  }
  func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
    let result = completion
    completion = nil
    if exitCode == 0 {
      result?.resume()
    } else {
      result?.resume(throwing: AppFailure("PTY process failed"))
    }
  }
  func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
}

private func fixtureCommand() throws -> TerminalLoginCommand {
  let agent = InstalledAgent(
    id: "test", name: "Test", version: "1", executable: "/bin/echo", arguments: [],
    environment: [:], directory: "/tmp")
  let method = AuthMethod(json: ["id": "login", "name": "Login", "type": "terminal", "args": []])!
  return try TerminalLoginCommand(
    agent: agent, method: method, directory: URL(fileURLWithPath: "/tmp"))
}
@MainActor private func waitForTerminal(_ condition: () -> Bool) async throws {
  for _ in 0..<300 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw AppFailure("Timed out waiting for terminal login")
}
