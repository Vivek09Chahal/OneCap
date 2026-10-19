import DLS
import SwiftUI

/// Shared compact surface for folder, mode, and model controls.
struct ComposerControlLabel<Content: View>: View {
    @Environment(\.dlsTheme) private var theme
    @State private var hovered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(DLSTypography.composerControl)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, DLSSpacing.sm)
            .frame(height: ChatLayout.sendButtonSize)
            .background(theme.colors.background.opacity(hovered ? 0.65 : 0.3), in: RoundedRectangle(cornerRadius: DLSRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: DLSRadius.small))
            .onHover { hovered = $0 }
    }
}
