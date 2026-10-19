import DLS
import SwiftUI

/// Persistent icon rail; chat history occupies its own neighboring sidebar.
struct AppSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Binding var selection: ContentView.Page?
    @Binding var showingArchive: Bool
    let openArchive: () -> Void
    
    var body: some View {
        VStack(spacing: DLSSpacing.lg) {
            VStack(spacing: DLSSpacing.sm) {
                ForEach(ContentView.Page.allCases) { page in
                    RailButton(title: page.rawValue, symbol: page.symbol, selected: selection == page && !showingArchive) {
                        showingArchive = false
                        selection = page
                    }
                    if page == .chat {
                        RailButton(title: "Archived chats", symbol: "archivebox", selected: showingArchive, action: openArchive)
                    }
                }
            }
            Spacer(minLength: DLSSpacing.lg)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(DLSTypography.navigationIcon)
                    .frame(width: DLSSize.avatar, height: DLSSize.avatar)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.textSecondary)
            .help("Appearance settings")
            .accessibilityLabel("Settings")
        }
        .padding(.vertical, DLSSpacing.md)
        .frame(width: ChatLayout.railWidth)
        .background(theme.colors.surface)
    }
}

private struct RailButton: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DLSTypography.navigationIcon)
                .frame(width: DLSSize.avatar, height: DLSSize.avatar)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.textSecondary)
                .background(
                    selected ? theme.colors.accentSubtle : .clear,
                    in: RoundedRectangle(cornerRadius: DLSRadius.medium))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
