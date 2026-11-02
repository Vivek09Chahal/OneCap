import DLS
import SwiftUI

/// Keep native button and split-menu behavior while making pointer focus clear.
struct FileChangeActionHover: ViewModifier {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var highlighted: Bool { hovered && isEnabled }

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: DLSRadius.small)
                    .fill(theme.colors.textPrimary)
                    .opacity(highlighted ? 0.08 : 0)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DLSRadius.small)
                    .strokeBorder(theme.colors.borderStrong, lineWidth: DLSSize.border)
                    .opacity(highlighted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}
