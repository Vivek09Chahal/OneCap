import Foundation

/// Each distribution prepares the same command; the coordinator publishes it atomically.
protocol AgentDistributionInstalling: Sendable {
    func install(staging: URL, destination: URL) async throws -> AgentCommand
}
