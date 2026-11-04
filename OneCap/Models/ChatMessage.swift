import Foundation

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    let role: String
    var text: String
    var thinkingTime: ThinkingTime?
    var replyState: ReplyState?
    var attachments: [ChatAttachment]?
    var changeSetID: UUID?
    var changeTrackingNotice: String?
    var toolActivities: [ACPToolActivity]?
    var thoughtText: String?
    
    mutating func appendResponseText(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        if thinkingTime?.isRunning == true { thinkingTime?.stop() }
        replyState = .responding
        text += chunk
    }

    mutating func finishToolActivities(as state: ReplyState) {
        guard let toolActivities else { return }
        self.toolActivities = toolActivities.map { activity in
            var activity = activity
            if activity.isActive {
                activity.status = state == .completed ? "completed"
                    : state == .failed ? "failed" : "stopped"
            }
            return activity
        }
    }

    var hasContent: Bool { replyState == .thinking || replyState == .responding || !(thoughtText ?? "").isEmpty || !text.isEmpty || !(attachments ?? []).isEmpty || changeSetID != nil || !(toolActivities ?? []).isEmpty }
    var contentForModel: String {
        let context = ChatAttachment.context(attachments ?? [])
        return context.isEmpty ? text : text + "\n\n" + context
    }

    var providerContent: Any {
        let images = (attachments ?? []).filter(\.isImage)
        guard !images.isEmpty else { return contentForModel }
        var blocks: [[String: Any]] = [["type": "text", "text": contentForModel]]
        for image in images {
            if let data = image.imageData, let mime = image.mimeType {
                blocks.append(["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]])
            }
        }
        return blocks
    }
}

enum ReplyState: String, Codable, Sendable {
    case thinking, responding, completed, stopped, failed
}

/// Frozen on the first answer text, even if the agent continues streaming afterward.
struct ThinkingTime: Codable, Sendable, Equatable {
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
