import DLS
import SwiftUI

struct AgentCard: View {
    @Environment(\.dlsTheme) private var theme
    let agent: Agent
    let installedVersion: String?
    let busy: Bool
    let uninstalling: Bool
    let canUninstall: Bool
    let install: () -> Void
    let uninstall: () -> Void
    @State private var confirmingUninstall = false
    
    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.lg) {
            AgentIconView(agent: agent)
            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                AgentCardHeader(agent: agent, displayedVersion: agent.canInstall ? nil : installedVersion)
                Text(agent.description)
                    .dlsFont(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DLSSpacing.md) {
                    Label(agent.installKind, systemImage: distributionSymbol)
                    Text(agent.license ?? "Agent terms apply")
                        .lineLimit(1)
                        .help(agent.license ?? "See the agent's website for its terms.")
                }
                .dlsFont(.caption)
                .foregroundStyle(theme.colors.textTertiary)
                if let note = agent.setupNote {
                    Label(note, systemImage: "info.circle")
                        .dlsFont(.caption)
                        .foregroundStyle(theme.colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if installedVersion != nil, let reason = AgentCompatibility.installationIssue(for: agent) {
                    Text("Update unavailable: \(reason)")
                        .dlsFont(.caption)
                        .foregroundStyle(theme.colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DLSSpacing.md) {
                AgentInstallAction(
                    available: agent.canInstall, latestVersion: agent.version,
                    installedVersion: installedVersion, busy: busy, uninstalling: uninstalling,
                    install: install)
                if installedVersion != nil && !uninstalling {
                    Button("Uninstall agent", systemImage: "trash") { confirmingUninstall = true }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                        .foregroundStyle(theme.colors.textSecondary)
                        .disabled(busy || !canUninstall)
                        .help(
                            canUninstall
                            ? "Uninstall \(agent.name)" : "Stop the current request before uninstalling")
                }
            }
            .fixedSize()
            .frame(minWidth: 120, minHeight: DLSSize.avatar, alignment: .trailing)
        }
        .padding(DLSSpacing.xl)
        .alert("Uninstall \(agent.name)?", isPresented: $confirmingUninstall) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive, action: uninstall).disabled(
                busy || uninstalling || !canUninstall)
        } message: {
            Text(
                "Removes this agent and its managed versions. Saved chats, shared runtimes, and sign-in files outside the installation folder are kept."
            )
        }
    }
    
    private var distributionSymbol: String {
        if agent.binary != nil { return "laptopcomputer" }
        if agent.distribution.npx != nil { return "terminal" }
        return "info.circle"
    }
}
