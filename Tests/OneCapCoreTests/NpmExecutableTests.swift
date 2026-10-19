import Foundation
import Testing

@testable import OneCapCore

@Test func linkedNativeNpmEntryIsResolvedAndLaunchedDirectlyAfterPublishing() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-native-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let stage = root.appendingPathComponent("stage")
  let package = stage.appendingPathComponent("node_modules/@xai-official/grok")
  let bin = package.appendingPathComponent("bin")
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  // Copy a real Mach-O executable: no network, vendor code, or account credentials needed.
  try FileManager.default.copyItem(
    at: URL(fileURLWithPath: "/usr/bin/true"), to: bin.appendingPathComponent("grok-native"))
  try FileManager.default.createSymbolicLink(
    atPath: bin.appendingPathComponent("grok").path,
    withDestinationPath: "./grok-native")
  let entry = try PackageValidation.resolvedExecutable("bin/grok", in: package, containedIn: stage)
  let destination = root.appendingPathComponent("published")
  let command = try NpmEntryCommand.make(
    entry: entry, staging: stage, destination: destination,
    node: URL(fileURLWithPath: "/unused/node"), arguments: ["agent", "stdio"])
  try FileManager.default.moveItem(at: stage, to: destination)
  #expect(
    command.executable
      == destination.appendingPathComponent("node_modules/@xai-official/grok/bin/grok-native").path)
  #expect(command.arguments == ["agent", "stdio"])
  #expect(FileManager.default.isExecutableFile(atPath: command.executable))
}

@Test func javascriptNpmEntryStillUsesManagedNode() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-js-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let package = root.appendingPathComponent("node_modules/example")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  try Data("#!/usr/bin/env node\nconsole.log('hello');".utf8).write(
    to: package.appendingPathComponent("cli.js"))
  let entry = try PackageValidation.resolvedExecutable("cli.js", in: package, containedIn: root)
  let command = try NpmEntryCommand.make(
    entry: entry, staging: root,
    destination: URL(fileURLWithPath: "/tmp/published"),
    node: URL(fileURLWithPath: "/managed/node"), arguments: ["acp"])
  #expect(command.executable == "/managed/node")
  #expect(command.arguments == ["/tmp/published/node_modules/example/cli.js", "acp"])
}

@Test func npmExecutableRejectsEscapingBrokenAndCyclicLinks() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-links-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let package = root.appendingPathComponent("node_modules/example")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  for (name, target) in [
    ("external", "/usr/bin/true"), ("broken", "missing"), ("cycle", "cycle"),
    ("parent", "../../../outside"),
  ] {
    try FileManager.default.createSymbolicLink(
      atPath: package.appendingPathComponent(name).path, withDestinationPath: target)
    #expect(throws: AppFailure.self) {
      try PackageValidation.resolvedExecutable(name, in: package, containedIn: root)
    }
  }
  try FileManager.default.createSymbolicLink(
    atPath: package.appendingPathComponent("outside-dir").path, withDestinationPath: "/usr/bin")
  #expect(throws: AppFailure.self) {
    try PackageValidation.resolvedExecutable("outside-dir/true", in: package, containedIn: root)
  }
  // The stricter API used by uninstall and extraction still rejects even internal links.
  #expect(throws: AppFailure.self) { try PackageValidation.containedPath("cycle", in: package) }
}
