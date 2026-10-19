import Foundation

extension AppStore {
    func reviewFileChanges(_ changes: FileChangeSet, path: String? = nil) {
        reviewedFilePath = path
        reviewedChanges = changes
    }

    func undoFileChanges(_ id: UUID) async {
        guard !sending, !applyingFileUndo,
              let changes = fileChanges.first(where: { $0.id == id }), changes.revertedAt == nil else { return }
        let chat = conversationID
        applyingFileUndo = true
        fileChangeError = nil
        defer { applyingFileUndo = false }
        do {
            try await fileChangeTracker.undo(changes)
            if conversationID == chat, let index = fileChanges.firstIndex(where: { $0.id == id }) {
                fileChanges[index].revertedAt = .now
                if reviewedChanges?.id == id { reviewedChanges = fileChanges[index] }
                fileTreeRevision = UUID()
                checkpointConversation(touch: false)
            } else if let chatIndex = conversations.firstIndex(where: { $0.id == chat }),
                      let changeIndex = conversations[chatIndex].fileChanges?.firstIndex(where: { $0.id == id }) {
                conversations[chatIndex].fileChanges?[changeIndex].revertedAt = .now
                persistHistory()
            }
        } catch {
            fileChangeError = error.localizedDescription
        }
    }
}
