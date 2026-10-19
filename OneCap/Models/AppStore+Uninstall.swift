import Foundation

extension AppStore {
    func uninstallAgent(_ id: String) async {
        guard !sending, !connecting, !installing.contains(id), !uninstalling.contains(id),
              let agent = installed.first(where: { $0.id == id })
                else { return }
        uninstalling.insert(id)
        defer { uninstalling.remove(id) }
        if chatUsesAgent && selectedAgentID == id {
            activeConnectionID = UUID()
            terminalLogin.cancel()
            acp.close(reason: "Uninstalling \(agent.name)…")
        }
        do {
            let result = try await installer.uninstall(agent, repository: repository)
            // Apply only this removal; other agents may have finished installing meanwhile.
            installed.removeAll { $0.id == id }
            if selectedAgentID == id {
                if chatUsesAgent { resetChat() }
                selectedAgentID =
                installed.first(where: { $0.id == result.state.selectedAgentID })?.id
                ?? installed.first(where: { AgentCompatibility.unavailableReason(for: $0.id) == nil })?.id
                if selectedAgentID == nil { status = "Install an agent to start chatting." }
            }
            if let cleanupError = result.cleanupError { error = cleanupError }
        } catch { self.error = "Could not uninstall \(agent.name): \(error.localizedDescription)" }
    }
}
