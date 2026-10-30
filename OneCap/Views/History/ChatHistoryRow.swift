import DLS
import SwiftUI

struct ChatHistoryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let conversation: ChatConversation
    let actions: ChatHistoryActions
    let isSelected: Bool
    @State private var renaming = false
    @State private var title = ""
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    private var isRunning: Bool {
        if conversation.id == store.conversationID { return store.sending }
        return store.chatSessions[conversation.id]?.sending == true
    }
    
    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            if isRunning {
                Circle()
                    .fill(theme.colors.success)
                    .frame(width: DLSSpacing.sm, height: DLSSpacing.sm)
                    .accessibilityHidden(true)
            }
            if renaming {
                TextField("Chat title", text: $title)
                    .font(DLSTypography.historyBody)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renaming = false }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused && renaming { commitRename() }
                    }
            } else {
                ClippedSingleLineText(conversation.title, fadeWidth: DLSSpacing.huge)
                    .font(DLSTypography.historyBody)
            }
        }
            .foregroundStyle(colorScheme == .dark ? Color.white : theme.colors.textPrimary)
            .font(DLSTypography.historyBody)
            .fontWeight(.regular)
            .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
            .listRowInsets(HistoryLayout.rowInsets)
            .listRowBackground(
                RoundedRectangle(cornerRadius: DLSRadius.small)
                    .fill(isSelected ? theme.colors.selection : Color.clear)
                    .padding(.horizontal, DLSSpacing.xs)
            )
            .help("\(conversation.title) · Updated \(conversation.updatedAt.formatted(.relative(presentation: .named)))")
            .accessibilityLabel(conversation.title)
            .accessibilityValue(isRunning ? "Task running" : "")
            .contextMenu {
                ChatHistoryMenu(
                    conversation: conversation,
                    rename: {
                        title = conversation.title
                        renaming = true
                        titleFocused = true
                    },
                    togglePin: { actions.togglePin(conversation.id) },
                    toggleArchive: { actions.toggleArchive(conversation.id) },
                    delete: { confirmingDelete = true })
            }
            .alert("Delete this chat?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { actions.delete(conversation.id) }
            } message: {
                Text("This permanently removes the conversation from this Mac.")
            }
    }
    private func commitRename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { actions.rename(conversation.id, trimmed) }
        renaming = false
    }
}
