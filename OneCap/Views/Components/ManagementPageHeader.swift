import DLS
import SwiftUI

struct ManagementPageHeader: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let subtitle: String
    var summary: String? = nil
    var summarySymbol = "checkmark.circle"
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DLSSpacing.lg) {
                Text(title).font(DLSTypography.catalogTitle)
                Spacer()
                if let summary {
                    Label(summary, systemImage: summarySymbol)
                        .font(DLSTypography.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            Text(subtitle).font(DLSTypography.body).foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DLSSpacing.sm)
    }
}
