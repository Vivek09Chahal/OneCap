import DLS
import SwiftUI

struct ToolActivityRow: View {
    @Environment(\.dlsTheme) private var theme
    let activity: ACPToolActivity

    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            Group {
                if activity.isActive {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: activity.status == "failed" ? "exclamationmark.circle"
                              : activity.status == "stopped" ? "stop.circle" : "checkmark")
                        .dlsFont(.caption)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text(activity.label)
                .dlsFont(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .help("\(activity.label) — \(activity.status.capitalized)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.label), \(activity.status.replacingOccurrences(of: "_", with: " "))")
    }
}

/// Group consecutive tools without changing their execution order.
struct ToolActivityList: View {
    let activities: [ACPToolActivity]

    private var groups: [ActivityGroup] {
        var groups: [ActivityGroup] = []
        for activity in activities {
            let category = ActivityCategory(kind: activity.kind)
            if groups.last?.category == category {
                groups[groups.count - 1].activities.append(activity)
            } else {
                groups.append(ActivityGroup(category: category, activities: [activity]))
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            ForEach(groups) { group in
                ToolActivityGroup(group: group)
            }
        }
    }
}

private enum ActivityCategory {
    case search, read, edit, execute, fetch, other

    init(kind: String?) {
        switch kind {
        case "search": self = .search
        case "read": self = .read
        case "edit", "delete", "move": self = .edit
        case "execute": self = .execute
        case "fetch": self = .fetch
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .search: "bolt"
        case .read: "doc.text"
        case .edit: "square.and.pencil"
        case .execute: "terminal"
        case .fetch: "globe"
        case .other: "gearshape"
        }
    }

    func title(count: Int) -> String {
        let noun: String = switch self {
        case .search: count == 1 ? "search" : "searches"
        case .read: count == 1 ? "file read" : "file reads"
        case .edit: count == 1 ? "file change" : "file changes"
        case .execute: count == 1 ? "command" : "commands"
        case .fetch: count == 1 ? "fetch" : "fetches"
        case .other: count == 1 ? "tool call" : "tool calls"
        }
        return "\(count) \(noun)"
    }
}

private struct ActivityGroup: Identifiable {
    let category: ActivityCategory
    var activities: [ACPToolActivity]
    var id: String { activities[0].id }
}

private struct ToolActivityGroup: View {
    let group: ActivityGroup
    @State private var isExpanded: Bool

    init(group: ActivityGroup) {
        self.group = group
        _isExpanded = State(initialValue: group.activities.contains(where: \.isActive))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            ActivityDisclosure(title: group.category.title(count: group.activities.count),
                               symbol: group.category.symbol, isExpanded: $isExpanded)
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    ForEach(group.activities) { activity in
                        ToolActivityRow(activity: activity)
                    }
                }
                .padding(.leading, 32)
                .overlay(alignment: .topLeading) {
                    ActivityBranch()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .frame(width: 22, height: 20)
                        .padding(.leading, 8)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

private struct ActivityBranch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: 0, y: rect.maxY))
        return path
    }
}
