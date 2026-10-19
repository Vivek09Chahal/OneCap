import DLS
import SwiftUI

struct ChatHistoryRow: View {
    @Environment(\.dlsTheme) private var theme
    let conversation: ChatConversation
    let actions: ChatHistoryActions
    let isSelected: Bool
    @State private var renaming = false
    @State private var title = ""
    @State private var confirmingDelete = false
    
    var body: some View {
        Text(conversation.title)
            .font(DLSTypography.historyBody)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, DLSSpacing.xs)
            .listRowBackground(
                RoundedRectangle(cornerRadius: DLSRadius.small)
                    .fill(isSelected ? theme.colors.selection : Color.clear)
                    .padding(.horizontal, DLSSpacing.xs)
            )
            .help(conversation.title)
            .accessibilityLabel(conversation.title)
            .contextMenu {
                ChatHistoryMenu(
                    conversation: conversation,
                    rename: {
                        title = conversation.title
                        renaming = true
                    },
                    togglePin: { actions.togglePin(conversation.id) },
                    toggleArchive: { actions.toggleArchive(conversation.id) },
                    delete: { confirmingDelete = true })
            }
            .alert("Rename chat", isPresented: $renaming) {
                TextField("Chat title", text: $title)
                Button("Cancel", role: .cancel) {}
                Button("Save") { actions.rename(conversation.id, title) }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("Delete this chat?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { actions.delete(conversation.id) }
            } message: {
                Text("This permanently removes the conversation from this Mac.")
            }
    }
}
