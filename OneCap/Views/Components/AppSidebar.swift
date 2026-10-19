import DLS
import SwiftUI

/// Persistent icon rail; chat history occupies its own neighboring sidebar.
struct AppSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Binding var selection: ContentView.Page?
    
    var body: some View {
        VStack(spacing: DLSSpacing.lg) {
            Button {
                selection = .chat
            } label: {
                MazeMark()
                    .stroke(
                        theme.colors.accent,
                        style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: DLSSize.iconMedium, height: DLSSize.iconMedium)
                    .frame(width: DLSSize.avatar, height: DLSSize.avatar)
            }
            .buttonStyle(.plain)
            .help("OneCap")
            .accessibilityLabel("OneCap workspace")
            
            VStack(spacing: DLSSpacing.sm) {
                ForEach(ContentView.Page.allCases) { page in
                    RailButton(page: page, selected: selection == page) { selection = page }
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
    let page: ContentView.Page
    let selected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .font(DLSTypography.navigationIcon)
                .frame(width: DLSSize.avatar, height: DLSSize.avatar)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.textSecondary)
                .background(
                    selected ? theme.colors.accentSubtle : .clear,
                    in: RoundedRectangle(cornerRadius: DLSRadius.medium))
        }
        .buttonStyle(.plain)
        .help(page.rawValue)
        .accessibilityLabel(page.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
