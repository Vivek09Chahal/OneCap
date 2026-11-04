import DLS
import SwiftUI

struct RegistryAgentSection: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let agents: [Agent]
    let installedVersions: [String: String]
    let installing: Set<String>
    let uninstalling: Set<String>
    let canUninstall: Bool
    let uninstall: (Agent) -> Void
    let install: (Agent) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            ManagementSectionHeader(title: title, count: agents.count)
            VStack(spacing: DLSSpacing.none) {
                ForEach(agents) { agent in
                    if agent.id != agents.first?.id {
                        Divider()
                            .overlay(theme.colors.border)
                            .padding(.horizontal, DLSSpacing.xl)
                    }
                    AgentCard(
                        agent: agent, installedVersion: installedVersions[agent.id],
                        busy: installing.contains(agent.id), uninstalling: uninstalling.contains(agent.id),
                        canUninstall: canUninstall, install: { install(agent) }, uninstall: { uninstall(agent) }
                    )
                }
            }
            .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DLSRadius.large)
                    .stroke(theme.colors.border, lineWidth: DLSSize.border))
        }
    }
}
