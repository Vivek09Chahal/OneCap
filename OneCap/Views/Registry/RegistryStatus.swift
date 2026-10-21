import DLS
import SwiftUI

struct RegistryStatus: View {
    @Environment(\.dlsTheme) private var theme
    let resultCount: Int
    let loading: Bool
    let updatedAt: Date?
    let refreshFailed: Bool
    
    var body: some View {
        HStack(spacing: DLSSpacing.md) {
            Text("\(resultCount) \(resultCount == 1 ? "agent" : "agents")")
                .font(DLSTypography.callout.weight(.medium))
            Spacer()
            if loading { ProgressView().controlSize(.mini) }
            Group {
                if loading {
                    Text("Refreshing catalog…")
                } else if refreshFailed {
                    Text("Refresh failed · Try again")
                } else if let updatedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Updated \(updatedAt, format: .relative(presentation: .named))")
                    }
                    .help(updatedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Not refreshed yet")
                }
            }
            .font(DLSTypography.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
        }
        .padding(.bottom, DLSSpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border).frame(height: DLSSize.border)
        }
    }
}
