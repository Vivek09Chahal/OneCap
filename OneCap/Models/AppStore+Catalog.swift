import Foundation

extension AppStore {
    func loadCatalog() async {
        guard !catalogLoaded else { return }
        await refresh()
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let registry = try await installer.catalog()
            let updated = registry.agents.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if agents != updated { agents = updated }
            catalogLoaded = true
            catalogUpdatedAt = .now
            catalogRefreshFailed = false
        } catch {
            self.error = error.localizedDescription
            catalogRefreshFailed = true
        }
    }
    func selectAgent(_ id: String?) {
        guard !sending else { return }
        if let id, let reason = AgentCompatibility.unavailableReason(for: id) {
            connectionError = reason
            status = reason
            return
        }
        guard selectedAgentID != id, id.map({ !uninstalling.contains($0) }) ?? true else { return }
        disconnectAgentForSelectionChange()
        selectedAgentID = id
        checkpointConversation(touch: false)
        Task {
            do { try await repository.selectAgent(id) } catch { self.error = error.localizedDescription }
        }
    }
    
    func install(_ agent: Agent) async {
        guard !installing.contains(agent.id), !uninstalling.contains(agent.id) else { return }
        installing.insert(agent.id)
        defer { installing.remove(agent.id) }
        do {
            let result = try await installer.install(agent)
            let state = try await repository.register(result)
            if let index = installed.firstIndex(where: { $0.id == result.id }) {
                installed[index] = result
            } else {
                installed.append(result)
            }
            if selectedAgentID == nil {
                selectedAgentID = state.selectedAgentID ?? result.id
                if messages.isEmpty && !sending { chatUsesAgent = true }
            }
        } catch { self.error = error.localizedDescription }
    }
}
