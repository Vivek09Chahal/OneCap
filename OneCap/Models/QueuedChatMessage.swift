import Foundation

struct QueuedChatMessage: Identifiable, Codable, Sendable, Equatable {
    let message: ChatMessage
    let usesAgent: Bool
    var id: UUID { message.id }
}

extension AppStore {
    func removeQueuedMessage(_ id: UUID) {
        queuedMessages.removeAll { $0.id == id }
        checkpointConversation(touch: false)
    }

    func canSendQueuedMessageNow(_ pending: QueuedChatMessage) -> Bool {
        let session = chatSession
        return session.queuedSendID == nil && !session.stoppingReply && !session.importingFiles
            && queuedMessageIsReady(pending, in: session)
    }

    /// An explicit send interrupts the current turn, then sends just the chosen message.
    /// Keep it queued until cancellation finishes and the same connection is ready.
    @discardableResult
    func sendQueuedMessageNow(_ id: UUID) async -> Bool {
        let session = chatSession
        guard let pending = session.queuedMessages.first(where: { $0.id == id }),
              canSendQueuedMessageNow(pending) else { return false }
        if pending.usesAgent, (pending.message.attachments ?? []).contains(where: \.isImage), !session.acp.supportsImages {
            session.connectionError = "This agent does not support image attachments. The queued message has been kept."
            return false
        }
        let providerID = session.selectedProviderID
        let agentID = session.selectedAgentID
        let connectionID = session.activeConnectionID
        session.queuedSendID = id
        defer { session.queuedSendID = nil }
        if session.sending {
            let currentTask = session.sendTask
            stopReply()
            await currentTask?.value
        }
        guard !Task.isCancelled, session.selectedProviderID == providerID,
              session.selectedAgentID == agentID, session.activeConnectionID == connectionID,
              !session.sending, !session.stoppingReply,
              let next = session.queuedMessages.first(where: { $0.id == id }),
              queuedMessageIsReady(next, in: session) else { return false }
        return startQueuedMessage(next, in: session)
    }

    /// Starts the next queued message; successful completion advances the queue again.
    func sendNextQueuedMessage(in targetSession: ChatSession? = nil) {
        let session = targetSession ?? chatSession
        guard !session.sending, !session.stoppingReply, session.queuedSendID == nil,
              let next = session.queuedMessages.first,
              queuedMessageIsReady(next, in: session) else { return }
        _ = startQueuedMessage(next, in: session)
    }

    private func queuedMessageIsReady(_ next: QueuedChatMessage, in session: ChatSession) -> Bool {
        !session.connecting && !session.applyingFileUndo && !session.savingReviewedFile
            && !session.acp.updatingConfiguration && next.usesAgent == session.chatUsesAgent
            && (next.usesAgent ? session.acp.sessionReady : providers.contains(where: { $0.id == session.selectedProviderID }))
    }

    private func startQueuedMessage(_ next: QueuedChatMessage, in session: ChatSession) -> Bool {
        if next.usesAgent, (next.message.attachments ?? []).contains(where: \.isImage), !session.acp.supportsImages {
            session.connectionError = "This agent does not support image attachments. The queued message has been kept."
            return false
        }
        session.queuedMessages.removeAll { $0.id == next.id }
        session.messages.append(next.message)
        generateReply(text: next.message.text, useAgent: next.usesAgent, in: session)
        return true
    }
}
