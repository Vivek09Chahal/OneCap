import DLS
import SwiftUI

struct RegistryStatus: View {
    @Environment(\.dlsTheme) private var theme
    let resultCount: Int
    let loading: Bool
    let status: String
    
    var body: some View {
        HStack(spacing: DLSSpacing.md) {
            Text("\(resultCount) \(resultCount == 1 ? "agent" : "agents")")
                .font(DLSTypography.captionStrong)
            Spacer()
            if loading { ProgressView().controlSize(.mini) }
            Text(loading ? "Refreshing catalog…" : status)
                .font(DLSTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.bottom, DLSSpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border).frame(height: DLSSize.border)
        }
    }
}
