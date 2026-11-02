import DLS
import SwiftUI

/// Explicit symbol dimensions keep native toolbar sizing consistent across pages.
struct ToolbarIconButton: View {
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarIcon(symbol: symbol, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(width: ChatLayout.toolbarControlSize, height: ChatLayout.toolbarControlSize)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Borderless toolbar menu icon. Caller passes the menu items.
struct ToolbarIconMenu<Content: View>: View {
    let title: String
    let symbol: String
    let content: () -> Content
    @State private var hovered = false

    var body: some View {
        Menu {
            content()
        } label: {
            Color.clear
                .frame(width: ChatLayout.toolbarControlSize, height: ChatLayout.toolbarControlSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: ChatLayout.toolbarControlSize, height: ChatLayout.toolbarControlSize)
        // Draw outside the native menu label so AppKit cannot tint or shrink the symbol.
        .overlay {
            ToolbarIcon(symbol: symbol, isHovered: hovered)
                .allowsHitTesting(false)
        }
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
    }
}

/// Buttons, sharing, and menus use the same symbol canvas in the toolbar.
struct ToolbarIcon: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    var isSelected = false
    var isHovered = false
    @State private var hovered = false

    @ViewBuilder private var icon: some View {
        switch symbol {
        case "sidebar.left":
            AppIcon("sidebar", size: ChatLayout.toolbarIconSize)
        case "doc.text.magnifyingglass":
            AppIcon("directory", size: ChatLayout.toolbarIconSize + 3)
        default:
            AppIcon(systemName: symbol, size: ChatLayout.toolbarIconSize)
        }
    }

    var body: some View {
        icon
            .font(DLSTypography.toolbarIcon)
            .foregroundStyle(isSelected ? theme.colors.accent : (hovered || isHovered) && isEnabled ? theme.colors.textPrimary : theme.colors.textSecondary)
            .opacity(isEnabled ? 1 : 0.4)
            .frame(width: ChatLayout.toolbarControlSize, height: ChatLayout.toolbarControlSize)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
