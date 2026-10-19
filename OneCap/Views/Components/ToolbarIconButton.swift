import DLS
import SwiftUI

/// Explicit symbol dimensions keep native toolbar sizing consistent across pages.
struct ToolbarIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .font(DLSTypography.toolbarIcon)
                .frame(width: DLSSize.iconToolbar, height: DLSSize.iconToolbar)
        }
        .accessibilityLabel(title)
    }
}
