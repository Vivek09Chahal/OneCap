import DLS
import SwiftUI

/// Persistent icon rail; chat history occupies its own neighboring sidebar.
struct AppSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Namespace private var selectionHighlight
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
        .background(selection == .settings ? Color.clear : theme.colors.surface)
    }

    private func pageButton(_ page: ContentView.Page) -> some View {
        RailButton(title: page.rawValue, iconName: page.iconName, selected: selection == page, selectionHighlight: selectionHighlight) {
            NavigationTrace.mark("sidebar clicked: \(page.rawValue)")
            selection = page
            didSelect(page)
            NavigationTrace.mark("sidebar action returned: \(page.rawValue)")
        }
    }
}

private struct RailButton: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.dlsReduceMotion) private var reduceMotion
    let title: String
    let iconName: String
    let selected: Bool
    let selectionHighlight: Namespace.ID
    let action: () -> Void
    @FocusState private var focused: Bool
    
    var body: some View {
        Button(action: action) {
            Group {
                if iconName == "plugins" { AppIcon(systemName: "personalhotspot", size: ChatLayout.railIconSize) }
                else { AppIcon(iconName, size: ChatLayout.railIconSize) }
            }
                .font(DLSTypography.navigationIcon)
                .frame(width: min(DLSSize.avatar, ChatLayout.railWidth), height: DLSSize.avatar)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.textSecondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: DLSRadius.small)
                            .fill(theme.colors.accentSubtle)
                            .frame(width: ChatLayout.railSelectionSize, height: ChatLayout.railSelectionSize)
                            .matchedGeometryEffect(id: "activeRailHighlight", in: selectionHighlight)
                    }
                }
                .contentShape(Rectangle())
                // Animate the rail decoration, not the page-selection transaction.
                // The latter also replaces native toolbar items and active editors.
                .animation(reduceMotion ? nil : .linear(duration: 0.18), value: selected)
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
