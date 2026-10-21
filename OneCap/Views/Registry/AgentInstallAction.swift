import DLS
import SwiftUI

struct AgentInstallAction: View {
    @Environment(\.dlsTheme) private var theme
    let available: Bool
    let latestVersion: String
    let installedVersion: String?
    let busy: Bool
    let uninstalling: Bool
    let install: () -> Void
    
    var body: some View {
        if busy || uninstalling {
            HStack(spacing: DLSSpacing.sm) {
                ProgressView().controlSize(.mini)
                Text(uninstalling ? "Uninstalling…" : "Installing…").font(DLSTypography.caption)
            }
            .accessibilityElement(children: .combine)
        } else if installedVersion == latestVersion || (installedVersion != nil && !available) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(DLSTypography.captionStrong)
                .foregroundStyle(theme.colors.success)
                .help(installedVersion.map { "Installed v\($0)" } ?? "Installed")
        } else if available {
            Button(installedVersion == nil ? "Install" : "Update", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help(
                    installedVersion.map { "Update v\($0) to v\(latestVersion)" }
                    ?? "Install this agent on your Mac")
        } else {
            Text("Not available")
                .font(DLSTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .help("This agent does not offer a supported installation for this Mac yet.")
        }
    }
}
