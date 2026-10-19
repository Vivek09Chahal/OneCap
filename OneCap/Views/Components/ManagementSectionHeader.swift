import DLS
import SwiftUI

struct ManagementSectionHeader: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let count: Int
    
    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            Text(title).font(DLSTypography.heading)
            Text("\(count)").font(DLSTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            Rectangle().fill(theme.colors.border).frame(height: DLSSize.border)
                .padding(.leading, DLSSpacing.sm)
                .accessibilityHidden(true)
        }
    }
}
