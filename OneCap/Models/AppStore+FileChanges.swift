import Foundation

extension AppStore {
    func saveReviewedFile(_ text: String, path: String, changesID: UUID, expected: String?) async throws {
        guard !sending, !applyingFileUndo, !savingReviewedFile else { throw AppFailure("Wait for the current operation before saving.") }
        guard let changes = fileChanges.first(where: { $0.id == changesID }), changes.revertedAt == nil,
              let original = changes.files.first(where: { $0.path == path }) else {
            throw AppFailure("These changes are no longer available for editing.")
        }
        let chat = conversationID
        savingReviewedFile = true
        defer { savingReviewedFile = false }
        try await fileChangeTracker.saveText(text, path: path, folder: changes.folder, expected: expected)
        let diff = await FileTextDiff.makeInBackground(before: original.before, after: text)
        let edit = FileEdit(path: path, before: original.before, after: text, permissions: original.permissions,
            additions: diff.added, deletions: diff.removed, diff: diff.text)
        if conversationID == chat, let index = fileChanges.firstIndex(where: { $0.id == changesID }),
           let file = fileChanges[index].files.firstIndex(where: { $0.path == path }) {
            fileChanges[index].files[file] = edit
            // The review reads the live changes directly; keep its presentation stable.
            // Only creating a missing file needs a directory refresh.
            if expected == nil { fileTreeRevision = UUID() }
            checkpointConversation(touch: false)
        }
    }

    func reviewFileChanges(_ changes: FileChangeSet, path: String? = nil) {
        reviewedFilePath = path
        reviewedChanges = changes
    }

    func restoreFileChanges(_ id: UUID) async {
        guard !sending, !applyingFileUndo, !savingReviewedFile,
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
