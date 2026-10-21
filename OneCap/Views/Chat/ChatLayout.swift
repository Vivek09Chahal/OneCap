import DLS
import SwiftUI

/// Shared app dimensions keep the composer and transcript on the same column.
enum ChatLayout {
    static let columnWidth: CGFloat = 760
    static let userMessageWidth: CGFloat = 560
    static let railWidth: CGFloat = 46
    static let titlebarExtraHeight: CGFloat = 0
    static let sendButtonSize: CGFloat = 32
}

extension View {
    func chatColumn() -> some View {
        frame(maxWidth: ChatLayout.columnWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DLSSpacing.xxxl)
    }
}
