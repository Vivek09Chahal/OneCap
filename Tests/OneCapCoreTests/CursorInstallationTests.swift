import Foundation
import Testing

@testable import OneCapCore

@Test func cursorOfficialMacArchivesArePinnedAndUnrelatedURLsAreNotTrusted() throws {
  for release in ["2026.10.16-e3cb207", "2026.10.19-6bbf2c4"] {
    for arch in ["arm64", "x64"] {
      let binary = BinaryDistribution(
        archive:
          "https://downloads.cursor.com/lab/\(release)/darwin/\(arch)/agent-cli-package.tar.gz",
        cmd: "./dist-package/cursor-agent", args: ["acp"], env: nil, sha256: nil)
      #expect(binary.verifiedSHA256?.count == 64)
      let agent = Agent(
        id: "cursor", name: "Cursor", version: "2026.10.16", description: "",
        repository: nil, website: nil, license: nil,
        distribution: .init(binary: [Agent.platform: binary], npx: nil, uvx: nil))
      #expect(agent.canInstall)
    }
  }
  for url in [
    "https://downloads.cursor.com.evil.test/lab/2026.10.16-e3cb207/darwin/arm64/agent-cli-package.tar.gz",
    "http://downloads.cursor.com/lab/2026.10.16-e3cb207/darwin/arm64/agent-cli-package.tar.gz",
    "https://downloads.cursor.com/lab/unreviewed/darwin/arm64/agent-cli-package.tar.gz",
  ] { #expect(KnownBinaryChecksums.sha256(for: url) == nil) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_CURSOR_ARCHIVE"] != nil))
func officialCursorArchiveInstallsAndLauncherRuns() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-cursor-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let path = try #require(ProcessInfo.processInfo.environment["ONECAP_CURSOR_ARCHIVE"])
  let release = ProcessInfo.processInfo.environment["ONECAP_CURSOR_RELEASE"] ?? "2026.10.19-6bbf2c4"
  let expectedVersion = String(release.split(separator: "-")[0])
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  #if arch(arm64)
    let arch = "arm64"
  #else
    let arch = "x64"
  #endif
  let binary = BinaryDistribution(
    archive:
      "https://downloads.cursor.com/lab/\(release)/darwin/\(arch)/agent-cli-package.tar.gz",
    cmd: "./dist-package/cursor-agent", args: ["acp"], env: nil, sha256: nil)
  let agent = Agent(
    id: "cursor", name: "Cursor", version: expectedVersion, description: "",
    repository: nil, website: nil, license: nil,
    distribution: .init(binary: [Agent.platform: binary], npx: nil, uvx: nil))
  let installed = try await AgentInstaller(
    root: root, downloader: CursorArchiveDownloader(archive: data)
  ).install(agent)
  #expect(installed.arguments == ["acp"])
  let version = try await ProcessRunner().run(installed.executable, ["--version"])
  #expect(version.contains(expectedVersion))
  let connection = await ACPConnection()
  try await connection.connect(installed, workspace: root)
  #expect(await connection.connected)
  await connection.close()
}

private struct CursorArchiveDownloader: Downloading {
  let archive: Data
  func data(_ url: URL) async throws -> Data { archive }
}
