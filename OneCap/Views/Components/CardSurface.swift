import DLS
import SwiftUI

private struct CardSurface: ViewModifier {
    @Environment(\.dlsTheme) private var theme
    var padding: CGFloat = DLSSpacing.xl
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DLSRadius.large).stroke(
                    theme.colors.border, lineWidth: DLSSize.border))
    }
}

extension View {
    func cardSurface(padding: CGFloat = DLSSpacing.xl) -> some View {
        modifier(CardSurface(padding: padding))
    }
}
