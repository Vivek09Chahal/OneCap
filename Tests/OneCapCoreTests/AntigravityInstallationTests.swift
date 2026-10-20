import Foundation
import Testing

@testable import OneCapCore

@Test func antigravityOfficialMacArchivesAreInstallableWithExactPins() throws {
  for arch in ["arm64", "x86_64"] {
    let agent = antigravityAgent(architecture: arch)
    #expect(agent.canInstall)
    #expect(agent.binary?.verifiedSHA256?.count == 64)
    #expect(agent.distributionKind == .binary)
    #expect(agent.iconURL != nil)
  }
  for url in [
    "http://dl.google.com/agy-extensions/releases/macos/agy-acp-server-1.4.1-darwin-arm64.zip",
    "https://dl.google.com.evil.test/agy-extensions/releases/macos/agy-acp-server-1.4.1-darwin-arm64.zip",
    "https://dl.google.com/agy-extensions/releases/macos/agy-acp-server-unknown-darwin-arm64.zip",
  ] {
    #expect(KnownBinaryChecksums.sha256(for: url) == nil)
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ONECAP_ANTIGRAVITY_ARCHIVE"] != nil))
func officialAntigravityArchiveInstallsAndInitializesACPWithoutSigningIn() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-antigravity-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let path = try #require(ProcessInfo.processInfo.environment["ONECAP_ANTIGRAVITY_ARCHIVE"])
  let archive = try Data(contentsOf: URL(fileURLWithPath: path))
  #if arch(arm64)
    let arch = "arm64"
  #else
    let arch = "x86_64"
  #endif
  let agent = antigravityAgent(architecture: arch)
  let installed = try await AgentInstaller(
    root: root, downloader: AntigravityArchiveDownloader(archive: archive)
  ).install(agent)
  #expect(installed.arguments.isEmpty)
  #expect(FileManager.default.isExecutableFile(atPath: installed.executable))
  #expect(FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: installed.directory).appendingPathComponent("localharness_external").path))
  let connection = await ACPConnection()
  do {
    try await connection.connect(installed, workspace: root)
    #expect(await connection.connected)
    #expect(await connection.authMethods.contains(where: \.isSupported))
    await connection.close()
  } catch {
    await connection.close()
    throw error
  }
}

private func antigravityAgent(architecture: String) -> Agent {
  let binary = BinaryDistribution(
    archive: "https://dl.google.com/agy-extensions/releases/macos/agy-acp-server-1.4.1-darwin-\(architecture).zip",
    cmd: "./agy_acp_server.par", args: nil, env: nil, sha256: nil)
  return Agent(
    id: "antigravity-acp", name: "Google Antigravity", version: "1.4.1",
    description: "Google’s AI coding agent", repository: nil,
    website: "https://antigravity.google/docs/ide/extensions", license: "proprietary",
    distribution: .init(binary: [Agent.platform: binary], npx: nil, uvx: nil),
    icon: "https://cdn.agentclientprotocol.com/registry/v1/latest/antigravity-acp.svg")
}

private struct AntigravityArchiveDownloader: Downloading {
  let archive: Data
  func data(_ url: URL) async throws -> Data { archive }
}
