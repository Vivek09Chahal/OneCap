import DLS
import SwiftUI

struct ThinkingTimeLabel: View {
    @Environment(\.dlsTheme) private var theme
    let timing: ThinkingTime
    
    var body: some View {
        Group {
            if timing.isRunning {
                TimelineView(.periodic(from: timing.startedAt, by: 0.1)) { context in
                    label(elapsed: timing.elapsed(at: context.date), running: true)
                }
            } else {
                label(elapsed: timing.elapsed(), running: false)
            }
        }
        .font(DLSTypography.caption)
        .monospacedDigit()
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.vertical, DLSSpacing.xxs)
    }
    
    private func label(elapsed: TimeInterval, running: Bool) -> some View {
        HStack(spacing: DLSSpacing.sm) {
            if running { ProgressView().controlSize(.mini) } else { Image(systemName: "timer") }
            Text(
                "\(running ? "Thinking" : "Thought for") \(elapsed.formatted(.number.precision(.fractionLength(1))))s"
            )
        }
    }
}
