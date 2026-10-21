import DLS
import SwiftUI

/// Conversation actions remain in the native toolbar; model controls live in the composer.
struct ChatToolbar: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var workspacePanelVisible: Bool
    let availableWidth: CGFloat
    
    var body: some ToolbarContent {
        ToolbarItem(id: "conversation-title", placement: .principal) {
            HStack(spacing: DLSSpacing.md) {
                Text("|").foregroundStyle(theme.colors.textSecondary).accessibilityHidden(true)
                ClippedSingleLineText(conversationTitle)
                    .frame(maxWidth: max(120, min(420, availableWidth - 280)))
                    .fixedSize(horizontal: true, vertical: false)
                Text("|").foregroundStyle(theme.colors.textSecondary).accessibilityHidden(true)
            }
            .font(DLSTypography.toolbarLabel)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(height: DLSSize.toolbarButton)
            .help(conversationTitle)
        }
        .sharedBackgroundVisibility(.hidden)
        if store.chatUsesAgent {
            ToolbarItem(id: "reload-agent", placement: .primaryAction) {
                ToolbarIconButton(title: "Reload agent", symbol: "arrow.clockwise") {
                    Task { await store.connect() }
                }
                .disabled(store.sending || store.connecting || store.selectedAgentID == nil)
                .help(store.connecting ? "Connecting to the selected agent…" : "Reconnect to the selected agent")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(id: "toggle-chat-changes", placement: .primaryAction) {
            ToolbarIconButton(title: "Toggle files panel", symbol: "doc.text.magnifyingglass", isSelected: workspacePanelVisible) {
                workspacePanelVisible.toggle()
            }
            .help(workspacePanelVisible ? "Hide files panel" : "Show directory and changed files")
            .accessibilityValue(workspacePanelVisible ? "Visible" : "Hidden")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var conversationTitle: String {
        store.conversations.first(where: { $0.id == store.conversationID })?.title ?? "New chat"
    }
}
