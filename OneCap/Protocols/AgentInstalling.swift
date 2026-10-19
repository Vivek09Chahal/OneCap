import Foundation

protocol AgentInstalling: Sendable {
    func catalog() async throws -> Registry
    func install(_ agent: Agent) async throws -> InstalledAgent
    func uninstall(_ agent: InstalledAgent, repository: AppRepository) async throws -> AgentUninstallResult
}
