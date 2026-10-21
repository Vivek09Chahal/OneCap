import DLS
import SwiftUI

struct RegistryView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var search = ""
    
    private var installedVersions: [String: String] {
        Dictionary(
            store.installed.map { ($0.id, $0.version) }, uniquingKeysWith: { _, latest in latest })
    }
    
    private var filtered: [Agent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.agents.filter { agent in
            agent.canInstall
            && (query.isEmpty
                || "\(agent.name) \(agent.id) \(agent.description)".localizedStandardContains(query))
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DLSSpacing.xxl) {
                RegistryHeader(
                    installedCount: filtered.filter { installedVersions[$0.id] != nil }.count)
                RegistryStatus(
                    resultCount: filtered.count, loading: store.loading,
                    updatedAt: store.catalogUpdatedAt, refreshFailed: store.catalogRefreshFailed)
                if store.loading && store.agents.isEmpty {
                    ProgressView("Loading agents…")
                        .frame(maxWidth: .infinity, minHeight: RegistryLayout.cardHeight)
                } else if filtered.isEmpty {
                    RegistryEmptyState(
                        searching: !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        catalogEmpty: store.agents.isEmpty, reset: { search = "" }, refresh: refresh
                    )
                } else {
                    agentSections
                }
                unavailableInstallations
                RegistryIntroduction()
            }
            .frame(maxWidth: RegistryLayout.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(DLSSpacing.xxxl)
        }
        .background(theme.colors.background)
        .navigationTitle("Agent Harnesses")
        .toolbar {
            ToolbarItem(id: "registry-search", placement: .automatic) {
                ToolbarSearchField(text: $search, prompt: "Search agents")
                    .frame(width: 220)
                    .overlay(
                        Capsule()
                            .stroke(theme.colors.borderStrong, lineWidth: DLSSize.border)
                     )
            }
            .sharedBackgroundVisibility(.hidden)
            RegistryToolbar(loading: store.loading, refresh: refresh)
        }
    }
    
    private var agentSections: some View {
        let versions = installedVersions
        let installed = filtered.filter { versions[$0.id] != nil }
        let available = filtered.filter { versions[$0.id] == nil && $0.canInstall }
        return VStack(alignment: .leading, spacing: DLSSpacing.xxxl) {
            if !installed.isEmpty { agentSection("Installed", agents: installed, versions: versions) }
            if !available.isEmpty { agentSection("Available", agents: available, versions: versions) }
        }
    }
    
    private func agentSection(_ title: String, agents: [Agent], versions: [String: String])
    -> some View
    {
        RegistryAgentSection(
            title: title, agents: agents, installedVersions: versions, installing: store.installing,
            uninstalling: store.uninstalling, canUninstall: !store.sending && !store.connecting,
            uninstall: { agent in Task { await store.uninstallAgent(agent.id) } },
            install: { agent in Task { await store.install(agent) } })
    }
    
    private var unavailableInstallations: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let unavailable = store.installed.filter {
            unavailableReason(for: $0) != nil
            && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
        return VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            if !unavailable.isEmpty {
                ManagementSectionHeader(title: "Unavailable installations", count: unavailable.count)
                ForEach(unavailable) { agent in 
                    UnavailableAgentRow(
                        agent: agent,
                        reason: unavailableReason(for: agent) ?? "Unavailable",
                        removing: store.uninstalling.contains(agent.id),
                        canRemove: !store.sending && !store.connecting && !store.installing.contains(agent.id),
                        uninstall: { Task { await store.uninstallAgent(agent.id) } })
                }
            }
        }
    }
    
    private func unavailableReason(for agent: InstalledAgent) -> String? {
        if let reason = AgentCompatibility.unavailableReason(for: agent.id) { return reason }
        if let entry = store.agents.first(where: { $0.id == agent.id }) {
            return AgentCompatibility.installationIssue(for: entry)
        }
        return "The catalog entry for this installation is unavailable. You can remove its installed copy here."
    }
    
    private func refresh() { Task { await store.refresh() } }
}
