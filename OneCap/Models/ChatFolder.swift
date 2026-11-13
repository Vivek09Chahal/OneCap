import Foundation

/// A user-created folder that organizes chats inside the app.
/// Unlike project folders, these are not backed by a directory on disk —
/// they contain chats and nothing else.
struct ChatFolder: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
    }
}

extension Array where Element == ChatConversation {
    /// Groups non-archived conversations by their in-app folder.
    var historyFolders: [ChatHistoryFolder] {
        historyFolders(in: [])
    }

    func historyFolders(in folders: [ChatFolder]) -> [ChatHistoryFolder] {
        var directory: [UUID: ChatFolder] = [:]
        for folder in folders {
            directory[folder.id] = folder
        }
        var chats: [UUID: [ChatConversation]] = [:]
        for conversation in self where conversation.folderID != nil {
            chats[conversation.folderID!, default: []].append(conversation)
        }
        let allFolderIDs = Set(directory.keys).union(Set(chats.keys))
        return allFolderIDs.compactMap { id in
            ChatHistoryFolder(
                folder: directory[id] ?? ChatFolder(name: ""),
                conversations: (chats[id] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            )
        }.sorted { $0.folder.name.localizedStandardCompare($1.folder.name) == .orderedAscending }
    }
}

struct ChatHistoryFolder: Identifiable {
    let folder: ChatFolder
    let conversations: [ChatConversation]
    var id: UUID { folder.id }
}
