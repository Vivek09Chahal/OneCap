import DLS
import SwiftUI

/// Conversation actions remain in the native toolbar; model controls live in the composer.
struct ChatToolbar: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var workspacePanelVisible: Bool
    
    var body: some ToolbarContent {
        ToolbarItem(id: "conversation-title", placement: .principal) {
            // Toolbar measurement must not write geometry back into SwiftUI
            // state. AppKit asserts if an item's size changes during layout.
            Text(conversationTitle)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 280, height: ChatLayout.toolbarControlSize)
            .dlsFont(.toolbarLabel)
            .foregroundStyle(theme.colors.textPrimary)
            .help(conversationTitle)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "reload-agent", placement: .automatic) {
            ToolbarIconButton(title: "Reload agent", symbol: "arrow.clockwise") {
                store.disconnectAgentForSelectionChange()
                Task { await store.connect() }
            }
            .disabled(!store.chatUsesAgent || store.sending || store.connecting || store.selectedAgentID == nil)
            .help(store.connecting ? "Connecting to the selected agent…" : "Reconnect to the selected agent")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "export-chat", placement: .automatic) {
            ChatExportMenu(conversationID: store.conversationID, toolbarStyle: true)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "share-chat", placement: .automatic) {
            ChatShareButton(transcript: store.exportTranscript(store.conversationID), toolbarStyle: true)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "toggle-chat-changes", placement: .automatic) {
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
