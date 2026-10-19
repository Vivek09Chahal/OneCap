import DLS
import SwiftUI

/// Retain removal access to a previously installed integration that is no longer supported.
struct UnavailableAgentRow: View {
    @Environment(\.dlsTheme) private var theme
    let agent: InstalledAgent
    let reason: String
    let removing: Bool
    let canRemove: Bool
    let uninstall: () -> Void
    @State private var confirming = false
    
    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.lg) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(theme.colors.warning)
            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                Text(agent.name).font(DLSTypography.heading)
                Text(reason).font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DLSSpacing.sm)
            if removing {
                ProgressView().controlSize(.mini)
            } else {
                Button("Uninstall", systemImage: "trash") { confirming = true }
                    .disabled(!canRemove)
            }
        }
        .padding(DLSSpacing.lg)
        .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
        .alert("Uninstall \(agent.name)?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive, action: uninstall).disabled(!canRemove || removing)
        } message: {
            Text("Removes its managed files. Saved chats and external sign-in files are kept.")
        }
    }
}
