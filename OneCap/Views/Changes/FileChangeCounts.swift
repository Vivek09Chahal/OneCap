import DLS
import SwiftUI

struct FileChangeCounts: View {
    @Environment(\.dlsTheme) private var theme
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: DLSSpacing.xs) {
            Text("+\(additions)").foregroundStyle(theme.colors.success)
            Text("−\(deletions)").foregroundStyle(theme.colors.danger)
        }
        .font(DLSTypography.caption).monospacedDigit().fixedSize()
        .accessibilityLabel("\(additions) lines added, \(deletions) lines removed")
    }
}
