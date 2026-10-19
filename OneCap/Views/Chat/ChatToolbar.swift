import DLS
import SwiftUI

enum ChatWorkspacePanel { case files, changes }

/// Conversation actions remain in the native toolbar; model controls live in the composer.
struct ChatToolbar: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Binding var workspacePanel: ChatWorkspacePanel?
    
    var body: some ToolbarContent {
        @Bindable var store = store
        ToolbarItem(id: "new-chat", placement: .navigation) {
            ToolbarIconButton(title: "New chat", symbol: "square.and.pencil") { store.resetChat() }
                .disabled(store.sending)
                .keyboardShortcut("n", modifiers: .command)
                .help("Start a new chat")
        }
        ToolbarItem(id: "chat-mode", placement: .navigation) {
            Picker(
                "Connection", selection: Binding(get: { store.chatUsesAgent }, set: store.selectChatMode)
            ) {
                Text("Provider chat").tag(false)
                Text("ACP agent").tag(true)
            }
            .pickerStyle(.menu)
            .disabled(store.sending)
            .help("Choose provider chat or an ACP agent")
        }
        ToolbarItem(id: "chat-agent", placement: .principal) {
            if store.chatUsesAgent { ChatAgentPicker() }
        }
        if store.chatUsesAgent {
            ToolbarItem(id: "reload-agent", placement: .primaryAction) {
                ToolbarIconButton(title: "Reload agent", symbol: "arrow.clockwise") {
                    Task { await store.connect() }
                }
                .disabled(store.sending || store.connecting || store.selectedAgentID == nil)
                .help(store.connecting ? "Connecting to the selected agent…" : "Reconnect to the selected agent")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(id: "toggle-workspace-files", placement: .primaryAction) {
            if store.workspace != nil {
                ToolbarIconButton(title: "Toggle folder sidebar", symbol: "sidebar.right") {
                    workspacePanel = workspacePanel == .files ? nil : .files
                }
                .help(workspacePanel == .files ? "Hide folder files" : "Show folder files")
                .accessibilityValue(workspacePanel == .files ? "Visible" : "Hidden")
            }
        }
        if store.workspace != nil {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(id: "toggle-chat-changes", placement: .primaryAction) {
            ToolbarIconButton(title: "Toggle chat changes", symbol: "doc.text.magnifyingglass") {
                workspacePanel = workspacePanel == .changes ? nil : .changes
            }
            .help(workspacePanel == .changes ? "Hide chat changes" : "Show files edited in this chat")
            .accessibilityValue(workspacePanel == .changes ? "Visible" : "Hidden")
        }
    }
}
