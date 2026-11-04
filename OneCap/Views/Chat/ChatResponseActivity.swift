import DLS
import SwiftUI

/// Shared compact header for thoughts and grouped tool activity.
struct ActivityDisclosure: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let symbol: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: DLSSpacing.sm) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .dlsFont(.caption)
            }
            .dlsFont(.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.vertical, DLSSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide \(title)" : "Show \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct ChatResponseActivity: View {
    @Environment(\.dlsTheme) private var theme
    let message: ChatMessage
    @State private var showsThoughts = false

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            if let thoughts = message.thoughtText, !thoughts.isEmpty {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    ActivityDisclosure(title: "Thought Process", symbol: "brain",
                                       isExpanded: $showsThoughts)
                    if showsThoughts {
                        Text(thoughts)
                            .dlsFont(.callout)
                            .foregroundStyle(theme.colors.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 26)
                    }
                }
            }
            if let activities = message.toolActivities, !activities.isEmpty {
                ToolActivityList(activities: activities)
            }
        }
    }
}

/// Animate only this small view; never invalidate the transcript on each tick.
struct ResponseProgressDots: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.dlsReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(theme.colors.textSecondary)
                        .frame(width: 4, height: 4)
                        .offset(y: reduceMotion ? 0 : -3 * sin(time * 5 - Double(index) * 0.7))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent is responding")
    }
}
