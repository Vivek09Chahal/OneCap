import DLS
import SwiftUI

/// Background-free label with a consistent hit area for composer controls.
struct ComposerControlLabel<Content: View>: View {
    @Environment(\.dlsTheme) private var theme
    @State private var hovered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(DLSTypography.composerControl)
            .foregroundStyle(hovered ? theme.colors.textPrimary : theme.colors.textSecondary)
            .padding(.horizontal, DLSSpacing.sm)
            .frame(height: ChatLayout.sendButtonSize)
            .contentShape(RoundedRectangle(cornerRadius: DLSRadius.small))
            .onHover { hovered = $0 }
    }
}
