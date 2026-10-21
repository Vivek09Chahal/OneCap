import Foundation

struct QueuedChatMessage: Identifiable, Codable, Sendable {
    let message: ChatMessage
    let usesAgent: Bool
    var id: UUID { message.id }
}

extension AppStore {
    func removeQueuedMessage(_ id: UUID) {
        queuedMessages.removeAll { $0.id == id }
        checkpointConversation(touch: false)
    }

    func sendNextQueuedMessage() {
        guard !sending, !connecting, !applyingFileUndo, !savingReviewedFile, !acp.updatingConfiguration,
              let next = queuedMessages.first,
              next.usesAgent == chatUsesAgent,
              next.usesAgent ? acp.sessionReady : selectedProvider != nil else { return }
        if next.usesAgent, (next.message.attachments ?? []).contains(where: \.isImage), !acp.supportsImages {
            connectionError = "This agent does not support image attachments. The queued message has been kept."
            return
        }
        queuedMessages.removeFirst()
        messages.append(next.message)
        generateReply(text: next.message.text, useAgent: next.usesAgent)
    }
}
