import Foundation

extension AppStore {
    func reviewFileChanges(_ changes: FileChangeSet, path: String? = nil) {
        reviewedFilePath = path
        reviewedChanges = changes
    }

    func restoreFileChanges(_ id: UUID) async {
        guard !sending, !applyingFileUndo,
              let changes = fileChanges.first(where: { $0.id == id }) else { return }
        let reapply = changes.revertedAt != nil
        let chat = conversationID
        applyingFileUndo = true
        fileChangeError = nil
        defer { applyingFileUndo = false }
        do {
            if reapply { try await fileChangeTracker.reapply(changes) }
            else { try await fileChangeTracker.undo(changes) }
            let revertedAt: Date? = reapply ? nil : .now
            if conversationID == chat, let index = fileChanges.firstIndex(where: { $0.id == id }) {
                fileChanges[index].revertedAt = revertedAt
                if reviewedChanges?.id == id { reviewedChanges = fileChanges[index] }
                fileTreeRevision = UUID()
                checkpointConversation(touch: false)
            } else if let chatIndex = conversations.firstIndex(where: { $0.id == chat }),
                      let changeIndex = conversations[chatIndex].fileChanges?.firstIndex(where: { $0.id == id }) {
                conversations[chatIndex].fileChanges?[changeIndex].revertedAt = revertedAt
                persistHistory()
            }
        } catch {
            fileChangeError = error.localizedDescription
        }
    }
}
