import Foundation
import Testing
@testable import OneCapCore

private func fixture(_ root: URL, id: String = "test.extension") throws -> URL {
    let source = root.appendingPathComponent("source-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let json = """
    {"apiVersion":1,"id":"\(id)","name":"Example","version":"1.0.0","summary":"Test extension",
    "entrypoint":"plugin.py","interpreter":"/usr/bin/python3",
    "commands":[{"id":"hello","title":"Hello","description":"A command","inputSchema":{"type":"object","properties":{}}}],
    "tools":[{"id":"echo","title":"Echo","description":"Echo text","inputSchema":{"type":"object","properties":{"text":{"type":"string"}}}}]}
    """
    try Data(json.utf8).write(to: source.appendingPathComponent("plugin.json"))
    try Data("""
    import json, sys
    r = json.load(sys.stdin)
    json.dump({"apiVersion": 1, "result": {"method": r["method"], "name": r["name"], "arguments": r["arguments"], "context": r["context"], "secret": __import__('os').environ.get('ONECAP_TEST_SECRET')}}, sys.stdout)
    """.utf8).write(to: source.appendingPathComponent("plugin.py"))
    return source
}

@Test func pluginPackagesDiscoverWithoutExecutingAndPersistTrust() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let directory = root.appendingPathComponent("installed")
    let registry = PluginPackageRegistry(directory: directory)
    try await registry.install(from: source)
    var package = try #require(try await registry.discover().packages.first)
    #expect(!package.enabled)
    await #expect(throws: AppFailure.self) { try await registry.approved(package) }
    try await registry.setEnabled(package, true)
    package = try #require(try await PluginPackageRegistry(directory: directory).discover().packages.first)
    #expect(package.enabled)
    let runtime = PluginPackageRuntime(registry: registry)
    let output = try await runtime.execute(package, kind: "commands/execute", name: "hello", arguments: .object([:]), workspace: nil)
    let response = try JSONDecoder().decode(PluginJSON.self, from: Data(output.utf8))
    #expect(response["method"]?.string == "commands/execute")
    #expect(response["secret"] == .null)
    // A source edit cannot affect the installed copy.
    try Data("broken".utf8).write(to: source.appendingPathComponent("plugin.py"))
    #expect(try await registry.discover().packages.first?.enabled == true)
    // An installed edit revokes trust, including snapshots already held by a chat.
    try Data("changed".utf8).write(to: package.directory.appendingPathComponent("plugin.py"))
    #expect(try await registry.discover().packages.first?.enabled == false)
    await #expect(throws: AppFailure.self) {
        try await runtime.execute(package, kind: "tools/call", name: "echo", arguments: .object([:]), workspace: nil)
    }
    try await registry.remove(package)
    #expect(try await registry.discover().packages.isEmpty)
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test func pluginPackageToolsUseHostApprovalAndRejectDisabledSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PluginPackageRegistry(directory: root.appendingPathComponent("installed"))
    try await registry.install(from: fixture(root))
    let initial = try #require(try await registry.discover().packages.first)
    try await registry.setEnabled(initial, true)
    let package = try #require(try await registry.discover().packages.first)
    let denied = ProviderPlugins(context: .init(packages: [package], packageRegistry: registry))
    let tools = try await denied.prepare()
    let alias = try #require(tools.first?["function"]?["name"]?.string)
    #expect(try await denied.execute(name: alias, arguments: "{}").contains("declined"))
    await denied.close()
    let allowed = ProviderPlugins(context: .init(packages: [package], packageRegistry: registry,
                                                 workspace: root, approve: { _, _, _ in true }))
    _ = try await allowed.prepare()
    let output = try await allowed.execute(name: alias, arguments: "{\"text\":\"hello\"}")
    #expect(output.contains("hello"))
    let response = try JSONDecoder().decode(PluginJSON.self, from: Data(output.utf8))
    #expect(response["context"]?["workspace"]?.string == root.path)
    try await registry.setEnabled(package, false)
    await #expect(throws: AppFailure.self) { try await allowed.execute(name: alias, arguments: "{}") }
    await allowed.close()
}

@Test func pluginDiscoveryIsolatesMalformedPackagesAndRejectsEscapes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let registry = PluginPackageRegistry(directory: root.appendingPathComponent("installed"))
    try await registry.install(from: source)
    await #expect(throws: AppFailure.self) { try await registry.install(from: source) }
    let broken = root.appendingPathComponent("installed/broken")
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: broken.appendingPathComponent("plugin.json"))
    let scan = try await registry.discover()
    #expect(scan.packages.count == 1)
    #expect(scan.issues.count == 1)
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: root)
    await #expect(throws: AppFailure.self) { try await registry.install(from: source) }
}

@Test func pluginRuntimeCancellationStopsHungCode() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    try Data("import time\ntime.sleep(60)\n".utf8).write(to: source.appendingPathComponent("plugin.py"))
    let registry = PluginPackageRegistry(directory: root.appendingPathComponent("installed"))
    try await registry.install(from: source)
    let initial = try #require(try await registry.discover().packages.first)
    try await registry.setEnabled(initial, true)
    let package = try #require(try await registry.discover().packages.first)
    let task = Task {
        try await PluginPackageRuntime(registry: registry).execute(package, kind: "commands/execute", name: "hello", arguments: .object([:]), workspace: nil)
    }
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
}

@Test @MainActor func pluginPackagesLoadAtStartupAndShareAcrossWindows() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    try await store.installPluginPackage(from: fixture(root))
    let package = try #require(store.pluginPackages.first)
    try await store.enablePluginPackage(package, enabled: true)
    let reopened = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await reopened.load()
    #expect(reopened.pluginPackages.first?.enabled == true)
    let window = reopened.makeWindowStore()
    try await window.enablePluginPackage(try #require(window.pluginPackages.first), enabled: false)
    #expect(reopened.pluginPackages.first?.enabled == false)
}

@Test func pluginPackagesRejectUnsupportedAPIsAndEntrypointTraversal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let manifest = source.appendingPathComponent("plugin.json")
    let original = try String(contentsOf: manifest, encoding: .utf8)
    let registry = PluginPackageRegistry(directory: root.appendingPathComponent("installed"))
    try Data(original.replacingOccurrences(of: "\"apiVersion\":1", with: "\"apiVersion\":99").utf8).write(to: manifest)
    await #expect(throws: AppFailure.self) { try await registry.install(from: source) }
    let outside = root.appendingPathComponent("outside.py")
    try Data("print('should never execute')".utf8).write(to: outside)
    try Data(original.replacingOccurrences(of: "\"entrypoint\":\"plugin.py\"", with: "\"entrypoint\":\"../outside.py\"").utf8).write(to: manifest)
    await #expect(throws: AppFailure.self) { try await registry.install(from: source) }
    #expect(try await registry.discover().packages.isEmpty)
}

@Test func pluginRuntimeRejectsOversizedOutputAndPluginFailures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for code in ["import sys\nsys.stdout.write('x' * (1024 * 1024 + 1))", "print('{\"apiVersion\":1,\"error\":{\"message\":\"private diagnostic\"}}')"] {
        let source = try fixture(root, id: "test.plugin-" + UUID().uuidString.lowercased())
        try Data(code.utf8).write(to: source.appendingPathComponent("plugin.py"))
        let registry = PluginPackageRegistry(directory: root.appendingPathComponent(UUID().uuidString))
        try await registry.install(from: source)
        let initial = try #require(try await registry.discover().packages.first)
        try await registry.setEnabled(initial, true)
        let package = try #require(try await registry.discover().packages.first)
        await #expect(throws: AppFailure.self) {
            try await PluginPackageRuntime(registry: registry).execute(package, kind: "commands/execute", name: "hello", arguments: .object([:]), workspace: nil)
        }
    }
}
