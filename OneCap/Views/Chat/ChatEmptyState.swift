import DLS
import SwiftUI

struct ChatEmptyState: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.navigateWorkspace) private var navigate
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
            HStack {
                Button("New chat", systemImage: "square.and.pencil") { store.newChat() }
                    .buttonStyle(.borderedProminent)
                Button("Add provider", systemImage: "key.horizontal") { navigate(.providers) }
                Button("Install agent", systemImage: "square.stack.3d.up") { navigate(.registry) }
            }
            .disabled(store.applyingFileUndo || store.savingReviewedFile)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
