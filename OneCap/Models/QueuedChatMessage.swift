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

    func sendNextQueuedMessage(in targetSession: ChatSession? = nil) {
        let session = targetSession ?? chatSession
        guard !session.sending, !session.connecting, !session.applyingFileUndo, !session.savingReviewedFile, !session.acp.updatingConfiguration,
              let next = session.queuedMessages.first,
              next.usesAgent == session.chatUsesAgent,
              next.usesAgent ? session.acp.sessionReady : providers.contains(where: { $0.id == session.selectedProviderID }) else { return }
        if next.usesAgent, (next.message.attachments ?? []).contains(where: \.isImage), !session.acp.supportsImages {
            session.connectionError = "This agent does not support image attachments. The queued message has been kept."
            return
        }
        session.queuedMessages.removeFirst()
        session.messages.append(next.message)
        generateReply(text: next.message.text, useAgent: next.usesAgent, in: session)
    }
}
