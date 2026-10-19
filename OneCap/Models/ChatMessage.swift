import Foundation

struct ChatMessage: Identifiable, Codable, Sendable {
    var id = UUID()
    let role: String
    var text: String
    var thinkingTime: ThinkingTime?
    var replyState: ReplyState?
    var attachments: [ChatAttachment]?
    var changeSetID: UUID?
    var changeTrackingNotice: String?
    
    var hasContent: Bool { !text.isEmpty || !(attachments ?? []).isEmpty || changeSetID != nil }
    var contentForModel: String {
        let context = ChatAttachment.context(attachments ?? [])
        return context.isEmpty ? text : text + "\n\n" + context
    }
}

enum ReplyState: String, Codable, Sendable {
    case thinking, responding, completed, stopped, failed
}

/// Frozen on the first answer text, even if the agent continues streaming afterward.
struct ThinkingTime: Codable, Sendable {
    let startedAt: Date
    private(set) var stoppedAt: Date?
    
    init(startedAt: Date = .now) { self.startedAt = startedAt }
    var isRunning: Bool { stoppedAt == nil }
    func elapsed(at now: Date = .now) -> TimeInterval {
        max(0, (stoppedAt ?? now).timeIntervalSince(startedAt))
    }
    mutating func stop(at date: Date = .now) {
        if stoppedAt == nil { stoppedAt = max(startedAt, date) }
    }
}
