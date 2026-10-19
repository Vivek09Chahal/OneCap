import SwiftUI

struct ChatHistoryMenu: View {
    let conversation: ChatConversation
    let rename: () -> Void
    let togglePin: () -> Void
    let toggleArchive: () -> Void
    let delete: () -> Void
    
    var body: some View {
        Button("Rename", systemImage: "pencil", action: rename)
        Button(
            conversation.isPinned ? "Unpin" : "Pin",
            systemImage: conversation.isPinned ? "pin.slash" : "pin",
            action: togglePin)
        Divider()
        Menu("Copy", systemImage: "doc.on.doc") {
            Button("Title") { ChatClipboard.copy(conversation.title) }
            Button("Conversation") { ChatClipboard.copyConversation(conversation.messages) }
                .disabled(conversation.messages.isEmpty)
        }
        Divider()
        Button(
            conversation.isArchived ? "Restore chat" : "Archive",
            systemImage: conversation.isArchived ? "arrow.uturn.backward" : "archivebox",
            action: toggleArchive)
        Button("Delete permanently…", systemImage: "trash", role: .destructive, action: delete)
    }
}
