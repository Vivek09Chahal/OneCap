import Foundation

extension AppStore {
    func loadHistory() async {
        do {
            let saved = try await conversationRepository.load()
            // Preserve any conversation started while disk/settings were loading.
            let currentIDs = Set(conversations.map(\.id))
            conversations.append(contentsOf: saved.filter { !currentIDs.contains($0.id) })
            conversations.sort { $0.updatedAt > $1.updatedAt }
            historyLoaded = true
            persistHistory()
        } catch {
            // Do not overwrite an unreadable history file with an empty list.
            self.error = "Could not load chat history: \(error.localizedDescription)"
        }
    }
    
    /// Snapshot on send, completion, and navigation. Never save a running timer to disk.
    func checkpointConversation(touch: Bool = true) {
        guard
            messages.contains(where: \.hasContent)
                || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draftAttachments.isEmpty
                || !queuedMessages.isEmpty
                else {
            if conversations.contains(where: { $0.id == conversationID && $0.messages.isEmpty }) {
                conversations.removeAll { $0.id == conversationID }
                persistHistory()
            }
            return
        }
        if let workspace { rememberProject(workspace) }
        let index = conversations.firstIndex { $0.id == conversationID }
        let previous = index.map { conversations[$0] }
        let previousDate = previous?.updatedAt ?? .now
        let snapshot = ChatConversation(
            id: conversationID,
            messages: messages.filter(\.hasContent).map { message in
                var saved = message
                saved.thinkingTime?.stop()
                if saved.replyState == .thinking || saved.replyState == .responding {
                    saved.replyState = .stopped
                }
                return saved
            },
            draft: draft, usesAgent: chatUsesAgent, agentID: selectedAgentID,
            providerID: selectedProviderID, workspace: workspace,
            updatedAt: touch ? .now : previousDate,
            customTitle: previous?.customTitle, generatedTitle: previous?.generatedTitle, pinnedAt: previous?.pinnedAt,
            archivedAt: previous?.archivedAt, draftAttachments: draftAttachments, fileChanges: fileChanges,
            queuedMessages: queuedMessages)
        if let index { conversations[index] = snapshot } else { conversations.append(snapshot) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persistHistory()
    }
    
    func openConversation(_ id: UUID) {
        guard id != conversationID, !sending,
              let conversation = conversations.first(where: { $0.id == id })
                else { return }
        resetChat()
        conversationID = conversation.id
        messages = conversation.messages
        fileChanges = conversation.fileChanges ?? []
        draft = conversation.draft
        draftAttachments = conversation.draftAttachments ?? []
        queuedMessages = conversation.queuedMessages ?? []
        chatUsesAgent = conversation.usesAgent
        selectedAgentID = conversation.agentID
        selectedProviderID = conversation.providerID
        workspace = conversation.workspace
        agentNeedsHistoryContext = !messages.isEmpty
    }
    
    func deleteConversation(_ id: UUID) {
        guard !sending else { return }
        titleTasks.removeValue(forKey: id)?.cancel()
        if id == conversationID {
            resetChat()
        }
        conversations.removeAll { $0.id == id }
        persistHistory()
    }
    
    func renameConversation(_ id: UUID, title: String) {
        let title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !sending, !title.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == id })
                else { return }
        conversations[index].customTitle = String(title.prefix(100))
        persistHistory()
    }
    
    func toggleConversationPin(_ id: UUID) {
        guard !sending, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].pinnedAt = conversations[index].isPinned ? nil : .now
        persistHistory()
    }
    
    func toggleConversationArchive(_ id: UUID) {
        guard !sending, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let archiving = !conversations[index].isArchived
        conversations[index].archivedAt = archiving ? .now : nil
        if archiving && id == conversationID { resetChat() }
        persistHistory()
    }
    
    func selectChatMode(_ usesAgent: Bool) {
        guard !sending, chatUsesAgent != usesAgent else { return }
        resetChat()
        chatUsesAgent = usesAgent
    }
    
    func selectProvider(_ id: UUID?) {
        guard !sending, selectedProviderID != id else { return }
        if !chatUsesAgent { resetChat(preservingDraft: true) }
        selectedProviderID = id
    }
    
    func persistHistory() {
        guard historyLoaded else { return }
        let snapshot = conversations
        let previous = historySaveTask
        historySaveTask = Task {
            // Ordered writes prevent an older snapshot replacing a newer one.
            await previous?.value
            do { try await conversationRepository.save(snapshot) } catch {
                self.error = "Could not save chat history: \(error.localizedDescription)"
            }
        }
    }
}
