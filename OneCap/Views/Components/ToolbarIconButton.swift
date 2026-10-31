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
        .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
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
                .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
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
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    var isSelected = false
    var isHovered = false
    @State private var hovered = false

    var body: some View {
        Image(systemName: symbol)
            // Native menus otherwise apply their accent tint and intrinsic symbol size.
            .renderingMode(.template)
            .resizable()
            // Preserve SF Symbols' optical alignment and stroke weight across glyph shapes.
            .font(DLSTypography.toolbarIcon)
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .scaledToFit()
            .frame(width: DLSSize.iconToolbar, height: DLSSize.iconToolbar)
            .foregroundStyle((hovered || isHovered) && isEnabled ? Color.white : Color.gray)
            .opacity(isEnabled ? 1 : 0.4)
            .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
