import CryptoKit
import Foundation
import Testing

@testable import OneCapCore

@Test func simultaneousInstallRequestsShareOneDownload() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let data = Data("local mock executable".utf8)
  let downloader = FixtureDownloader(data: data)
  let installer = AgentInstaller(root: root, downloader: downloader)
  let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let binary = BinaryDistribution(
    archive: "https://example.com/agent", cmd: "./agent", args: nil, env: nil, sha256: hash)
  let agent = Agent(
    id: "test", name: "Test", version: "1", description: "", repository: nil,
    website: nil, license: nil,
    distribution: .init(binary: [Agent.platform: binary], npx: nil, uvx: nil))
  async let first = installer.install(agent)
  async let second = installer.install(agent)
  let results = try await (first, second)
  #expect(results.0.directory == results.1.directory)
  #expect(await downloader.requests == 1)
  #expect(FileManager.default.isExecutableFile(atPath: results.0.executable))
}

@Test func sharedRuntimeFailureCanBeRetried() async {
  let downloader = FixtureDownloader(data: nil)
  let runtime = NodeRuntime(root: temporaryRoot(), downloader: downloader)
  async let first: URL? = try? runtime.binary()
  async let second: URL? = try? runtime.binary()
  let results = await (first, second)
  #expect(results.0 == nil && results.1 == nil)
  #expect(await downloader.requests == 1)
  _ = try? await runtime.binary()
  #expect(await downloader.requests == 2)
}

@Test func concurrentRepositoryWritesKeepBothAgents() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("state.json")
  let repository = AppRepository(url: url)
  func agent(_ id: String) -> InstalledAgent {
    InstalledAgent(
      id: id, name: id, version: "1", executable: "/bin/echo", arguments: [], environment: [:],
      directory: root.path)
  }
  async let first = repository.register(agent("first"))
  async let second = repository.register(agent("second"))
  _ = try await (first, second)
  let reloaded = try await AppRepository(url: url).load()
  #expect(Set(reloaded.installed.map(\.id)) == ["first", "second"])
}

@Test func processRunnerHandlesParallelOutputAndFailures() async throws {
  let runner = ProcessRunner()
  async let first = runner.run("/bin/echo", ["first"])
  async let second = runner.run("/bin/echo", ["second"])
  let outputs = try await (first, second)
  #expect(outputs.0 == "first\n")
  #expect(outputs.1 == "second\n")
  await #expect(throws: AppFailure.self) { try await runner.run("/usr/bin/false", []) }
}

@Test func processRunnerPropagatesCancellation() async throws {
  let task = Task { try await ProcessRunner().run("/bin/sleep", ["30"]) }
  try await Task.sleep(for: .milliseconds(50))
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
}

private func temporaryRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-concurrency-\(UUID().uuidString)")
}

private actor FixtureDownloader: Downloading {
  let response: Data?
  private(set) var requests = 0
  init(data: Data?) { response = data }
  func data(_ url: URL) async throws -> Data {
    requests += 1
    try await Task.sleep(for: .milliseconds(20))
    guard let response else { throw AppFailure("Fixture download failed") }
    return response
  }
}
