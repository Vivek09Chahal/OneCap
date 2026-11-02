import DLS
import SwiftUI

/// Shared app dimensions keep the composer and transcript on the same column.
enum ChatLayout {
    static let contentMaxWidth: CGFloat = 800
    static let railWidth: CGFloat = 43
    static let railIconSize: CGFloat = 18
    static let railSelectionSize: CGFloat = 30
    static let toolbarControlSize: CGFloat = DLSSize.toolbarButton - 3
    static let toolbarIconSize: CGFloat = DLSSize.iconToolbar * toolbarControlSize / DLSSize.toolbarButton
    static let titlebarExtraHeight: CGFloat = 0
    static let sendButtonSize: CGFloat = 32
}

extension View {
    func chatColumn() -> some View {
        frame(maxWidth: ChatLayout.contentMaxWidth)
            .padding(.horizontal, DLSSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
