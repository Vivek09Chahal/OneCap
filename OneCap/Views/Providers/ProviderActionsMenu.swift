import DLS
import SwiftUI

struct ProviderActionsMenu: View {
    @Environment(\.dlsTheme) private var theme
    let provider: Provider
    let busy: Bool
    let remove: () -> Void
    
    var body: some View {
        Menu {
            Button("Copy model ID", systemImage: "cpu") { ChatClipboard.copy(provider.model) }
            Button("Copy endpoint URL", systemImage: "link") { ChatClipboard.copy(provider.baseURL) }
            Divider()
            Button("Remove provider…", systemImage: "trash", role: .destructive, action: remove).disabled(
                busy)
        } label: {
            Image(systemName: "ellipsis").font(DLSTypography.navigationIcon)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Actions for \(provider.name)")
        .accessibilityLabel("Actions for \(provider.name)")
    }
}
