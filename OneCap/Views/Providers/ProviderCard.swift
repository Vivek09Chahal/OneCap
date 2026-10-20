import DLS
import SwiftUI

struct ProviderCard: View {
    @Environment(\.dlsTheme) private var theme
    let provider: Provider
    let selected: Bool
    let busy: Bool
    let openChat: () -> Void
    let remove: () async -> Void
    @State private var confirmingRemoval = false
    @State private var removing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            HStack(spacing: DLSSpacing.md) {
                Image(systemName: "network").font(DLSTypography.navigationIcon)
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: DLSSize.avatar, height: DLSSize.avatar)
                    .background(
                        theme.colors.accentSubtle, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
                VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                    Text(provider.name).font(DLSTypography.heading).lineLimit(1).help(provider.name)
                    Text("OpenAI-compatible API").font(DLSTypography.caption).foregroundStyle(
                        theme.colors.textSecondary)
                }
                Spacer(minLength: DLSSpacing.sm)
                if selected {
                    Label("Selected", systemImage: "checkmark.circle.fill").font(DLSTypography.caption)
                        .foregroundStyle(theme.colors.success)
                }
                ProviderActionsMenu(
                    provider: provider, busy: busy || removing, remove: { confirmingRemoval = true })
            }
            ProviderDetails(provider: provider)
            Divider().overlay(theme.colors.border)
            HStack {
                Label("Key stored in Keychain", systemImage: "lock.shield")
                    .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                Spacer()
                if removing { ProgressView().controlSize(.mini) }
                Button("Open chat", systemImage: "arrow.up.right", action: openChat)
                    .buttonStyle(.bordered).disabled(busy || removing)
            }
        }
        .cardSurface()
        .alert("Remove \(provider.name)?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removing = true
                Task {
                    await remove()
                    removing = false
                }
            }.disabled(busy)
        } message: {
            Text(
                "This removes the provider and its saved API key. Existing conversations remain in history."
            )
        }
    }
}
