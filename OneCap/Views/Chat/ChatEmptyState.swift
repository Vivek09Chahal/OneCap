import DLS
import SwiftUI
import Lottie

struct ChatEmptyState: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.navigateWorkspace) private var navigate
    let useAgent: Bool
    var body: some View {
        VStack(spacing: DLSSpacing.lg) {
//            Image(systemName: "sparkle").font(DLSTypography.heroIcon).foregroundStyle(theme.colors.accent)
            LottieView {
                try await DotLottieFile.named("emptyChat")
            }
            .playing(loopMode: .repeat(1))
            .frame(width: 200, height: 200)
            .foregroundStyle(theme.colors.accent)
            
            Text("A little space for big ideas.").dlsFont(.emptyStateTitle)
            Text(
                useAgent
                ? "Choose an installed agent to start chatting.\nAdd a project folder when you want to work with its files."
                : "Connect your API key in Providers, then start a conversation."
            )
            .foregroundStyle(theme.colors.textSecondary).multilineTextAlignment(.center)
            HStack {
                Button { store.newChat() } label: {
                    Label { Text("New chat") } icon: { AppIcon("edit") }
                }
                    .buttonStyle(.borderedProminent)
                Button { navigate(.providers) } label: {
                    Label { Text("Add provider") } icon: { AppIcon("keys") }
                }
                Button { navigate(.registry) } label: {
                    Label { Text("Install agent") } icon: { AppIcon("bot") }
                }
            }
            .disabled(store.applyingFileUndo || store.savingReviewedFile)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NavigateWorkspaceKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (ContentView.Page) -> Void = { _ in }
}
extension EnvironmentValues {
    var navigateWorkspace: @MainActor @Sendable (ContentView.Page) -> Void {
        get { self[NavigateWorkspaceKey.self] }
        set { self[NavigateWorkspaceKey.self] = newValue }
    }
}
