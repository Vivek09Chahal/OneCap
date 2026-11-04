import Foundation
import Testing
@testable import OneCapCore

@Test func duplicateOpenCodeReleaseAppearsOnceAndKeepsInstalledEntry() {
    let original = openCodeEntry(id: "opencode")
    let alias = openCodeEntry(id: "opencode-v2")
    let entries = [alias, original]
    #expect(AgentCompatibility.registryEntries(entries, installedIDs: []).map(\.id) == [original.id])
    #expect(AgentCompatibility.registryEntries(entries, installedIDs: [original.id]).map(\.id) == [original.id])
    #expect(AgentCompatibility.registryEntries(entries, installedIDs: [alias.id]).map(\.id) == [alias.id])
    // Existing installations must retain their management controls.
    #expect(AgentCompatibility.registryEntries(entries, installedIDs: [original.id, alias.id]) == entries)
}

@Test func differentOpenCodeReleasesAndUnverifiedBinariesRemainVisible() {
    let original = openCodeEntry(id: "opencode")
    for alias in [
        openCodeEntry(id: "opencode-v2", version: "3.0.0"),
        openCodeEntry(id: "opencode-v2", checksum: String(repeating: "b", count: 64)),
        openCodeEntry(id: "opencode-v2", checksum: nil),
        openCodeEntry(id: "opencode-v2", arguments: ["different-mode"]),
    ] {
        let entries = [original, alias]
        #expect(AgentCompatibility.registryEntries(entries, installedIDs: []) == entries)
    }
    #expect(AgentCompatibility.registryEntries([original], installedIDs: []) == [original])
}

private func openCodeEntry(
    id: String, version: String = "2.2.5", checksum: String? = String(repeating: "a", count: 64),
    arguments: [String] = ["acp"]
) -> Agent {
    Agent(
        id: id, name: id == "opencode" ? "OpenCode" : "OpenCode V2", version: version,
        description: "The open source coding agent", repository: "https://github.com/anomalyco/opencode",
        website: "https://opencode.ai", license: "MIT",
        distribution: .init(binary: [Agent.platform: .init(
            archive: "https://example.com/\(id).zip", cmd: "./opencode", args: arguments,
            env: nil, sha256: checksum)], npx: nil, uvx: nil))
}
