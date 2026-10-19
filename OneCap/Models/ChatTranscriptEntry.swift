import Foundation

/// Pair messages and timing using one immutable snapshot. Lazy rows never keep
/// an array index into the live transcript while authentication or edits replace it.
struct ChatTranscriptEntry: Identifiable, Sendable {
    let message: ChatMessage
    let thinkingTime: ThinkingTime?
    var id: UUID { message.id }

    static func make(from messages: [ChatMessage]) -> [Self] {
        messages.enumerated().compactMap { index, message in
            guard message.role == "user" || message.hasContent else { return nil }
            let next = messages.index(after: index)
            let timing = message.role == "user" && messages.indices.contains(next)
                && messages[next].role == "assistant" ? messages[next].thinkingTime : nil
            return Self(message: message, thinkingTime: timing)
        }
    }
}
