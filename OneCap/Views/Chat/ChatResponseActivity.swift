import DLS
import SwiftUI

struct ChatResponseActivity: View {
    @Environment(\.dlsTheme) private var theme
    let message: ChatMessage
    @State private var showsThoughts = false
    @State private var showsCommands = false

    private var commands: [ACPToolActivity] {
        (message.toolActivities ?? []).filter { $0.kind == "execute" }
    }

    var body: some View {
        let thoughts = message.thoughtText ?? ""
        let commands = commands
        if !thoughts.isEmpty || !commands.isEmpty {
            VStack(alignment: .leading, spacing: DLSSpacing.md) {
                HStack(spacing: DLSSpacing.lg) {
                    if !thoughts.isEmpty {
                        ActivityToggle(title: "Thought Process", symbol: "brain",
                                       isExpanded: $showsThoughts)
                    }
                    if !commands.isEmpty {
                        ActivityToggle(
                            title: commands.count == 1 ? "1 command" : "\(commands.count) commands",
                            symbol: "terminal", isExpanded: $showsCommands)
                    }
                }
                .dlsFont(.callout)

                if showsThoughts, !thoughts.isEmpty {
                    Text(thoughts)
                        .dlsFont(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .activityDetail(theme: theme)
                }
                if showsCommands, !commands.isEmpty {
                    LazyVStack(alignment: .leading, spacing: DLSSpacing.sm) {
                        ForEach(commands) { command in
                            CommandActivityRow(command: command)
                        }
                    }
                    .activityDetail(theme: theme)
                }
            }
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.bottom, message.text.isEmpty ? DLSSpacing.none : DLSSpacing.lg)
        }
    }
}

private struct ActivityToggle: View {
    let title: String
    let symbol: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: DLSSpacing.sm) {
                Image(systemName: symbol)
                Text(title)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .dlsFont(.caption)
            }
            .fixedSize()
            .padding(.vertical, DLSSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide \(title)" : "Show \(title)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct CommandActivityRow: View {
    @Environment(\.dlsTheme) private var theme
    let command: ACPToolActivity

    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.sm) {
            Group {
                if command.isActive {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: command.status == "failed" ? "exclamationmark.circle"
                          : command.status == "stopped" ? "stop.circle" : "checkmark")
                        .dlsFont(.caption)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text(command.label)
                .dlsFont(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .help(command.status.replacingOccurrences(of: "_", with: " ").capitalized)
        .accessibilityElement(children: .combine)
        .accessibilityValue(command.status.replacingOccurrences(of: "_", with: " "))
    }
}

private extension View {
    func activityDetail(theme: DLSTheme) -> some View {
        padding(.leading, DLSSpacing.lg)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.colors.textTertiary.opacity(0.35))
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 8)
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
