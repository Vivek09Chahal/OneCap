import DLS
import SwiftUI

struct ToolActivityRow: View {
    @Environment(\.dlsTheme) private var theme
    let activity: ACPToolActivity

    private var symbol: String {
        if activity.status == "failed" { return "exclamationmark.circle" }
        switch activity.kind {
        case "execute": return "terminal"
        case "edit", "delete", "move": return "square.and.pencil"
        case "read": return "doc.text"
        case "search": return "magnifyingglass"
        case "fetch": return "globe"
        default: return "gearshape"
        }
    }

    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            Image(systemName: symbol)
                .font(DLSTypography.navigationIcon)
                .frame(width: DLSSize.iconSmall)
                .accessibilityHidden(true)
            Text(activity.label)
                .font(DLSTypography.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .help(activity.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.phase): \(activity.label)")
    }
}
