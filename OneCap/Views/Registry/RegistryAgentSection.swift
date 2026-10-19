import DLS
import SwiftUI

struct RegistryAgentSection: View {
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: RegistryLayout.cardWidth), spacing: DLSSpacing.lg)],
                spacing: DLSSpacing.lg
            ) {
                ForEach(agents) { agent in
                    AgentCard(
                        agent: agent, installedVersion: installedVersions[agent.id],
                        busy: installing.contains(agent.id), uninstalling: uninstalling.contains(agent.id),
                        canUninstall: canUninstall, install: { install(agent) }, uninstall: { uninstall(agent) }
                    )
                }
            }
        }
    }
}
