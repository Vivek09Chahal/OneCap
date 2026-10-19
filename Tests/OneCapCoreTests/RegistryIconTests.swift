import Foundation
import Testing

@testable import OneCapCore

@Test func registryIconURLsDecodeWithoutBreakingOlderRegistryEntries() throws {
    let old = #"{"id":"agent","name":"Agent","version":"1.0.0","description":"Test","distribution":{"npx":{"package":"agent@1.0.0"}}}"#
    let legacy = try JSONDecoder().decode(Agent.self, from: Data(old.utf8))
    #expect(legacy.icon == nil)
    #expect(legacy.iconURL == nil)
    var agent = legacy
    agent.icon = "https://cdn.agentclientprotocol.com/registry/v1/latest/claude-acp.svg"
    let roundTrip = try JSONDecoder().decode(Agent.self, from: JSONEncoder().encode(agent))
    #expect(roundTrip.iconURL?.absoluteString == agent.icon)
    for invalid in ["", "/icon.svg", "file:///tmp/icon.svg", "javascript:alert(1)", "http://example.com/icon.svg", "https://"] {
        agent.icon = invalid
        #expect(agent.iconURL == nil)
    }
}
