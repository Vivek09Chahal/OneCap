import DLS
import SwiftUI

struct SectionHeading: View {
    @Environment(\.dlsTheme) private var theme
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            Text(eyebrow.uppercased()).font(DLSTypography.eyebrow)
                .tracking(DLSSize.eyebrowTracking).foregroundStyle(theme.colors.accent)
            Text(title).font(DLSTypography.pageTitle)
            Text(subtitle).font(DLSTypography.body).foregroundStyle(theme.colors.textSecondary).fixedSize(
                horizontal: false, vertical: true)
        }
    }
}
