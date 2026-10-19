import DLS
import SwiftUI

struct ChatEmptyState: View {
    @Environment(\.dlsTheme) private var theme
    let useAgent: Bool
    var body: some View {
        VStack(spacing: DLSSpacing.lg) {
            Image(systemName: "sparkle").font(DLSTypography.heroIcon).foregroundStyle(theme.colors.accent)
            Text("A little space for big ideas.").font(DLSTypography.emptyStateTitle)
            Text(
                useAgent
                ? "Choose an installed agent to start chatting.\nAdd a project folder when you want to work with its files."
                : "Connect your API key in Providers, then start a conversation."
            )
            .foregroundStyle(theme.colors.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
