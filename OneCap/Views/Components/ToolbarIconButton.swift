import DLS
import SwiftUI

/// Explicit symbol dimensions keep native toolbar sizing consistent across pages.
struct ToolbarIconButton: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .font(DLSTypography.toolbarIcon)
                .frame(width: DLSSize.iconToolbar, height: DLSSize.iconToolbar)
                .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
