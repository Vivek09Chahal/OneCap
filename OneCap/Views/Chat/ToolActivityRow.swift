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
                .dlsFont(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .help(activity.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.phase): \(activity.label)")
    }
}

/// Keep the summary mounted between tool updates so fast commands never flash away.
struct ToolActivityList: View {
    @Environment(\.dlsTheme) private var theme
    let activities: [ACPToolActivity]
    @State private var isExpanded = false

    private var latestActivity: ACPToolActivity? {
        activities.last(where: \.isActive) ?? activities.last
    }

    var body: some View {
        if let latestActivity {
            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: DLSSpacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .dlsFont(.caption)
                            .frame(width: DLSSize.iconSmall)
                            .accessibilityHidden(true)
                        ToolActivityRow(activity: latestActivity)
                        Spacer(minLength: DLSSpacing.sm)
                        Text("\(activities.count)")
                            .dlsFont(.caption)
                    }
                    .foregroundStyle(theme.colors.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide command history" : "Show command history")
                .accessibilityLabel("\(latestActivity.label), \(activities.count) tool activities")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                if isExpanded {
                    VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                        ForEach(activities) { activity in
                            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                                Text(activity.label)
                                    .dlsFont(.callout)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(statusLabel(activity))
                                    .dlsFont(.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, DLSSize.iconSmall + DLSSpacing.sm)
                }
            }
        }
    }

    private func statusLabel(_ activity: ACPToolActivity) -> String {
        switch activity.status {
        case "pending": "Pending"
        case "in_progress": "Running"
        case "completed": "Completed"
        case "failed": "Failed"
        case "stopped": "Stopped"
        default: activity.status.capitalized
        }
    }
}
