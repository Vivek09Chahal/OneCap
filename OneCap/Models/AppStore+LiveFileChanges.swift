import Foundation

extension AppStore {
    /// Poll disk independently of tool labels: agents may edit through shell commands too.
    func trackLiveFileChanges(in session: ChatSession, baseline: FileSnapshot, replyID: UUID) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(900))
                    var changes = try await session.fileChangeTracker.changes(since: baseline, replyID: replyID)
                    try Task.checkCancellation()
                    changes?.id = replyID
                    if changes?.files != session.liveFileChanges?.files {
                        session.liveFileChanges = changes
                        session.fileTreeRevision = UUID()
                    }

                } catch is CancellationError { return }
                catch {
                    // A transient read failure must not interrupt the agent. The final
                    // snapshot reports persistent failures in the transcript.
                }
            }
        }
    }

}
