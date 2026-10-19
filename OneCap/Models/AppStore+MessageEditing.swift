import Foundation

extension AppStore {
    func retryAuthenticatedMessage() {
        guard authenticationNeedsRetry, chatUsesAgent, acp.sessionReady,
              let id = lastUserMessageID, canEditMessage(id) else { return }
        beginEditing(id)
        if saveEditedMessage() { connectionError = nil }
    }

    var lastUserMessageID: UUID? { messages.last(where: { $0.role == "user" })?.id }
    
    func canEditMessage(_ id: UUID) -> Bool {
        !sending && !connecting && !applyingFileUndo && !acp.updatingConfiguration && id == lastUserMessageID
    }
    
    func beginEditing(_ id: UUID) {
        guard canEditMessage(id), let message = messages.first(where: { $0.id == id }) else { return }
        editingMessageID = id
        editedMessageText = message.text
    }
    
    func cancelEditing() {
        editingMessageID = nil
        editedMessageText = ""
    }
    
    @discardableResult
    func saveEditedMessage() -> Bool {
        guard let id = editingMessageID, canEditMessage(id),
              (!editedMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(messages.first(where: { $0.id == id })?.attachments ?? []).isEmpty),
              let index = messages.firstIndex(where: { $0.id == id })
                else { return false }
        let ready =
        chatUsesAgent ? acp.sessionReady : providers.contains { $0.id == selectedProviderID }
        guard ready else {
            error = "Wait for the agent or provider to be ready before resending."
            return false
        }
        let text = editedMessageText
        messages[index].text = text
        // Only replace the latest turn's answer; earlier user/assistant messages remain intact.
        messages.removeSubrange((index + 1)..<messages.endIndex)
        cancelEditing()
        generateReply(text: text, useAgent: chatUsesAgent, replacingLastTurn: true)
        return true
    }
}
