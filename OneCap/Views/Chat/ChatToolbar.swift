import DLS
import SwiftUI

enum ChatWorkspacePanel { case files, changes }

/// Conversation actions remain in the native toolbar; model controls live in the composer.
struct ChatToolbar: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var workspacePanel: ChatWorkspacePanel?
    let availableWidth: CGFloat
    let newChat: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(id: "chat-selection", placement: .navigation) {
            if store.chatUsesAgent { ChatAgentPicker() } else { ChatProviderPicker() }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "conversation-title", placement: .principal) {
            Text(conversationTitle)
                .font(DLSTypography.toolbarLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: max(100, min(300, availableWidth * 0.35)), alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
                .help(conversationTitle)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "new-chat", placement: .primaryAction) {
            ToolbarIconButton(title: "New chat", symbol: "square.and.pencil", action: newChat)
                .disabled(store.sending || store.applyingFileUndo)
                .keyboardShortcut("n", modifiers: .command)
                .help("Start a new chat")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
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
        ToolbarItem(id: "toggle-workspace-files", placement: .primaryAction) {
            if store.workspace != nil {
                ToolbarIconButton(title: "Toggle folder sidebar", symbol: "sidebar.right", isSelected: workspacePanel == .files) {
                    workspacePanel = workspacePanel == .files ? nil : .files
                }
                .help(workspacePanel == .files ? "Hide folder files" : "Show folder files")
                .accessibilityValue(workspacePanel == .files ? "Visible" : "Hidden")
            }
        }
        .sharedBackgroundVisibility(.hidden)
        if store.workspace != nil {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(id: "toggle-chat-changes", placement: .primaryAction) {
            ToolbarIconButton(title: "Toggle chat changes", symbol: "doc.text.magnifyingglass", isSelected: workspacePanel == .changes) {
                workspacePanel = workspacePanel == .changes ? nil : .changes
            }
            .help(workspacePanel == .changes ? "Hide chat changes" : "Show files edited in this chat")
            .accessibilityValue(workspacePanel == .changes ? "Visible" : "Hidden")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var conversationTitle: String {
        store.conversations.first(where: { $0.id == store.conversationID })?.title ?? "New chat"
    }
}
