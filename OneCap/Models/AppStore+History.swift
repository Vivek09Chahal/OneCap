import Foundation

extension AppStore {
    func loadHistory() async {
        do {
            let saved = try await conversationRepository.load()
            // Preserve any conversation started while disk/settings were loading.
            let currentIDs = Set(conversations.map(\.id))
            let merged = (conversations + saved.filter { !currentIDs.contains($0.id) })
                .sorted { $0.updatedAt > $1.updatedAt }
            if conversations != merged { conversations = merged }
            historyLoaded = true
            persistHistory()
        } catch {
            // Do not overwrite an unreadable history file with an empty list.
            self.error = "Could not load chat history: \(error.localizedDescription)"
        }
    }
    
    /// Snapshot on send, completion, and navigation. Never save a running timer to disk.
    func checkpointConversation(touch: Bool = true, session targetSession: ChatSession? = nil) {
        let session = targetSession ?? chatSession
        guard
            session.messages.contains(where: \.hasContent)
                || !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !session.draftAttachments.isEmpty
                || !session.queuedMessages.isEmpty
                else {
            if conversations.contains(where: { $0.id == session.conversationID && $0.messages.isEmpty }) {
                conversations.removeAll { $0.id == session.conversationID }
                persistHistory()
            }
            return
        }
        if let workspace = session.workspace { rememberProject(workspace) }
        let index = conversations.firstIndex { $0.id == session.conversationID }
        let previous = index.map { conversations[$0] }
        let previousDate = previous?.updatedAt ?? .now
        let snapshot = ChatConversation(
            id: session.conversationID,
            messages: session.messages.filter(\.hasContent).map { message in
                var saved = message
                saved.thinkingTime?.stop()
                if saved.replyState == .thinking || saved.replyState == .responding {
                    saved.replyState = .stopped
                }
                return saved
            },
            draft: session.draft, usesAgent: session.chatUsesAgent, agentID: session.selectedAgentID,
            providerID: session.selectedProviderID, workspace: session.workspace,
            updatedAt: touch ? .now : previousDate,
            customTitle: previous?.customTitle, generatedTitle: previous?.generatedTitle, pinnedAt: previous?.pinnedAt,
            archivedAt: previous?.archivedAt, draftAttachments: session.draftAttachments, fileChanges: session.fileChanges,
            queuedMessages: session.queuedMessages)
        guard previous != snapshot else { return }
        if let index { conversations[index] = snapshot } else { conversations.append(snapshot) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persistHistory()
    }
    
    func openConversation(_ id: UUID) {
        guard id != conversationID, !applyingFileUndo, !savingReviewedFile,
              let conversation = conversations.first(where: { $0.id == id })
                else { return }
        resetChat()
        if let session = chatSessions[id] {
            chatSession = session
            return
        }
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
        guard chatSessions[id]?.sending != true else { return }
        titleTasks.removeValue(forKey: id)?.cancel()
        if id == conversationID {
            resetChat()
        }
        chatSessions.removeValue(forKey: id)?.acp.close()
        conversations.removeAll { $0.id == id }
        persistHistory()
    }
    
    func renameConversation(_ id: UUID, title: String) {
        let title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !sending, !title.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == id })
                else { return }
        let compact = String(title.prefix(100))
        guard conversations[index].customTitle != compact else { return }
        conversations[index].customTitle = compact
        persistHistory()
    }
    
    func toggleConversationPin(_ id: UUID) {
        guard !sending, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].pinnedAt = conversations[index].isPinned ? nil : .now
        persistHistory()
    }
    
    func toggleConversationArchive(_ id: UUID) {
        guard chatSessions[id]?.sending != true, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
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
        // A removed provider must be replaceable without abandoning its saved chat.
        if !chatUsesAgent && selectedProvider != nil { resetChat(preservingDraft: true) }
        selectedProviderID = id
        if !chatUsesAgent {
            connectionError = nil
            checkpointConversation(touch: false)
        }
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
