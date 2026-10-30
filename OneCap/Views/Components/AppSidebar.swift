import DLS
import SwiftUI

/// Persistent icon rail; chat history occupies its own neighboring sidebar.
struct AppSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Binding var selection: ContentView.Page?
    var didSelect: (ContentView.Page) -> Void = { _ in }
    
    var body: some View {
        VStack(spacing: DLSSpacing.lg) {
            VStack(spacing: DLSSpacing.sm) {
                ForEach(ContentView.Page.allCases.filter { $0 != .skills && $0 != .settings }) { page in
                    pageButton(page)
                }
            }
            Spacer(minLength: DLSSpacing.lg)
            pageButton(.skills)
            pageButton(.settings)
        }
        .padding(.vertical, DLSSpacing.md)
        .frame(width: ChatLayout.railWidth)
        .fixedSize(horizontal: true, vertical: false)
        .background(theme.colors.surface)
    }

    private func pageButton(_ page: ContentView.Page) -> some View {
        RailButton(title: page.rawValue, symbol: page.symbol, selected: selection == page) {
            selection = page
            didSelect(page)
        }
    }
}

private struct RailButton: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool
    
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .font(DLSTypography.navigationIcon)
                .frame(width: DLSSize.iconCompact, height: DLSSize.iconCompact)
                .frame(width: DLSSize.avatar, height: DLSSize.avatar)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.textSecondary)
                .background {
                    RoundedRectangle(cornerRadius: DLSRadius.medium)
                        .fill(selected ? theme.colors.accentSubtle : .clear)
                        .padding(DLSSpacing.xxs)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .overlay {
            RoundedRectangle(cornerRadius: DLSRadius.medium)
                .stroke(focused ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
