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
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            AgentCardHeader(agent: agent)
            Text(agent.description)
                .font(DLSTypography.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .help(agent.description)
            if let note = agent.setupNote {
                Label(note, systemImage: "info.circle")
                    .font(DLSTypography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DLSSpacing.none)
            HStack(spacing: DLSSpacing.sm) {
                Label(agent.installKind, systemImage: distributionSymbol)
                    .font(DLSTypography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: DLSSpacing.none)
            }
            Divider().overlay(theme.colors.border)
            HStack(spacing: DLSSpacing.md) {
                Text(agent.license ?? "Agent terms apply")
                    .font(DLSTypography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .help(agent.license ?? "See the agent's website for its terms.")
                Spacer(minLength: DLSSpacing.sm)
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
            .frame(height: DLSSize.iconLarge)
        }
        .frame(maxWidth: .infinity, minHeight: RegistryLayout.cardHeight, alignment: .topLeading)
        .cardSurface()
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
