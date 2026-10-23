import Foundation
import Observation

/// Live state belongs to one conversation, including its process and in-flight reply.
@MainActor @Observable final class ChatSession {
    var messages: [ChatMessage] = []
    var fileChanges: [FileChangeSet] = []
    var reviewedChanges: FileChangeSet?
    var reviewedFilePath: String?
    var applyingFileUndo = false
    var savingReviewedFile = false
    var fileChangeError: String?
    var fileTreeRevision = UUID()
    @ObservationIgnored let fileChangeTracker = FileChangeTracker()
    var chatUsesAgent = false
    var draft = ""
    var draftAttachments: [ChatAttachment] = []
    var queuedMessages: [QueuedChatMessage] = []
    var importingFiles = false
    @ObservationIgnored var attachmentImportID = UUID()
    var editingMessageID: UUID?
    var editedMessageText = ""
    var stoppingReply = false
    var sending = false
    var connecting = false
    var connectionError: String?
    var authenticationNeedsRetry = false
    var status = "Choose a provider or connect an agent to begin."
    var selectedProviderID: UUID?
    var selectedAgentID: String?
    var workspace: URL?
    let acp = ACPConnection()
    let terminalLogin: TerminalLoginCoordinator
    @ObservationIgnored var agentNeedsHistoryContext = false
    var conversationID = UUID()
    @ObservationIgnored var activeConnectionID = UUID()
    @ObservationIgnored var replyID: UUID?
    @ObservationIgnored var sendTask: Task<Void, Never>?

    init(openLoginURL: @escaping @MainActor (URL) -> Bool) {
        terminalLogin = TerminalLoginCoordinator(openURL: openLoginURL)
    }
}
