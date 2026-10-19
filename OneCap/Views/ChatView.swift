import DLS
import SwiftUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @State private var workspacePanel: ChatWorkspacePanel?
    @State private var workspaceWidth: CGFloat = 0
    var startNewChat: (() -> Void)? = nil
    
    var body: some View {
        HSplitView {
            conversation
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            if workspacePanel == .files, let folder = store.workspace {
                WorkspaceFileTreeSidebar(folder: folder)
                    .id(folder)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 360, maxHeight: .infinity)
            } else if workspacePanel == .changes {
                SessionChangesSidebar()
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 380, maxHeight: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { workspaceWidth = $0 }
        .navigationTitle(
            store.conversations.first(where: { $0.id == store.conversationID })?.title ?? "New chat"
        )
        .toolbar {
            ChatToolbar(workspacePanel: $workspacePanel, availableWidth: workspaceWidth) {
                if let startNewChat { startNewChat() } else { store.resetChat() }
            }
        }
        .toolbar(removing: .title)
        .sheet(item: Binding(get: { store.reviewedChanges }, set: { store.reviewedChanges = $0 })) { changes in
            FileChangesReview(changes: changes)
        }
        .task(id: store.agentConnectionKey) {
            if store.agentConnectionKey != nil { await store.connect() }
        }
    }

    @ViewBuilder private var conversation: some View {
        @Bindable var store = store
        VStack(spacing: DLSSpacing.none) {
            if store.messages.isEmpty {
                ChatEmptyState(useAgent: store.chatUsesAgent)
            } else {
                ChatTranscript(
                    messages: store.messages,
                    editableMessageID: !store.sending && !store.connecting && !store.acp.updatingConfiguration
                    ? store.lastUserMessageID : nil,
                    editingMessageID: store.editingMessageID, editedText: $store.editedMessageText,
                    canResend: !store.acp.updatingConfiguration
                    && (store.chatUsesAgent ? store.acp.sessionReady : store.selectedProviderID != nil),
                    beginEdit: store.beginEditing, saveEdit: { store.saveEditedMessage() },
                    cancelEdit: store.cancelEditing)
            }
            VStack(spacing: DLSSpacing.md) {
                if let error = store.fileChangeError { FileChangeUndoNotice(message: error) }
                if store.chatUsesAgent {
                    if store.connecting {
                        Text(store.status)
                            .font(DLSTypography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = store.connectionError { ChatConnectionNotice(message: error) }
                }
                ChatComposer(
                    draft: $store.draft, sending: store.sending,
                    stopping: store.stoppingReply,
                    canSend: !store.connecting && !store.importingFiles && !store.acp.updatingConfiguration
                    && (store.chatUsesAgent ? store.acp.sessionReady : store.selectedProviderID != nil),
                    status: store.chatUsesAgent
                    ? store.status
                    : "Chats are saved on this Mac.",
                    send: send, stop: store.stopReply,
                    attachments: store.draftAttachments, importingFiles: store.importingFiles,
                    removeAttachment: store.removeAttachment,
                    leading: {
                        ChatWorkspaceBar()
                        if store.chatUsesAgent { ChatModePicker() }
                    },
                    trailing: { ChatModelPicker() }
                )
                .disabled(store.editingMessageID != nil || store.applyingFileUndo)
            }
            .chatColumn()
            .padding(.top, DLSSpacing.md)
            .padding(.bottom, DLSSpacing.lg)
        }
    }
    
    private func send() {
        guard !store.sending, !store.connecting, !store.importingFiles, !store.applyingFileUndo,
              !store.acp.updatingConfiguration,
              store.chatUsesAgent ? store.acp.sessionReady : store.selectedProviderID != nil
                else { return }
        let text = store.draft
        store.draft = ""
        store.send(text, useAgent: store.chatUsesAgent)
    }
}
