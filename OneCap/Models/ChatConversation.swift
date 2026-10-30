import Foundation

/// A local transcript and the connection settings needed to continue it.
struct ChatConversation: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var messages: [ChatMessage]
    var draft: String
    var usesAgent: Bool
    var agentID: String?
    var providerID: UUID?
    var workspace: URL?
    var updatedAt: Date
    var customTitle: String?
    var generatedTitle: String?
    var pinnedAt: Date?
    var archivedAt: Date?
    var draftAttachments: [ChatAttachment]?
    var fileChanges: [FileChangeSet]? = nil
    var queuedMessages: [QueuedChatMessage]? = nil
    
    var isPinned: Bool { pinnedAt != nil }
    var isArchived: Bool { archivedAt != nil }
    
    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let generatedTitle, !generatedTitle.isEmpty { return generatedTitle }
        let source = messages.first(where: { $0.role == "user" })?.text ?? draft
        let compact = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compact.isEmpty
        ? messages.first?.attachments?.first?.name ?? draftAttachments?.first?.name ?? "New chat"
        : String(compact.prefix(100))
    }
    
    func matches(_ query: String) -> Bool {
        query.isEmpty || title.localizedStandardContains(query)
        || messages.contains { $0.text.localizedStandardContains(query) }
        || (workspace?.lastPathComponent.localizedStandardContains(query) ?? false)
    }
}

struct ChatHistoryProject: Identifiable {
    let folder: URL
    let conversations: [ChatConversation]
    var id: String { folder.standardizedFileURL.path }
}

extension Array where Element == ChatConversation {
    var historyChats: [ChatConversation] {
        filter { $0.workspace == nil && !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var historyProjects: [ChatHistoryProject] { historyProjects(in: []) }
    
    func historyProjects(in folders: [URL]) -> [ChatHistoryProject] {
        var directories: [String: URL] = [:]
        var chats: [String: [ChatConversation]] = [:]
        for folder in folders {
            directories[folder.standardizedFileURL.path] = folder
        }
        for conversation in self {
            guard let folder = conversation.workspace else { continue }
            let path = folder.standardizedFileURL.path
            directories[path] = folder
            chats[path, default: []].append(conversation)
        }
        return directories.map { path, folder in
            ChatHistoryProject(
                folder: folder,
                conversations: (chats[path] ?? []).sorted { $0.updatedAt > $1.updatedAt })
        }.sorted {
            let left = $0.conversations.first?.updatedAt ?? .distantPast
            let right = $1.conversations.first?.updatedAt ?? .distantPast
            return left != right
            ? left > right
            : $0.folder.path.localizedStandardCompare($1.folder.path) == .orderedAscending
        }
    }
}

struct ChatHistoryDateGroup: Identifiable {
    let title: String
    let conversations: [ChatConversation]
    var id: String { title }
}

extension Array where Element == ChatConversation {
    func historyDateGroups(now: Date = .now, calendar: Calendar = .current) -> [ChatHistoryDateGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let week = calendar.date(byAdding: .day, value: -7, to: today)!
        let month = calendar.date(byAdding: .day, value: -30, to: today)!
        let titles = ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Older"]
        let groups = Dictionary(grouping: sorted { $0.updatedAt > $1.updatedAt }) { chat in
            chat.updatedAt >= today ? 0 : chat.updatedAt >= yesterday ? 1
                : chat.updatedAt >= week ? 2 : chat.updatedAt >= month ? 3 : 4
        }
        return titles.enumerated().compactMap { index, title in
            groups[index].map { ChatHistoryDateGroup(title: title, conversations: $0) }
        }
    }
}
