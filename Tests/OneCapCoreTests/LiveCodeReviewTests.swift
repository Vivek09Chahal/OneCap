import Foundation
import Testing
@testable import OneCapCore

@Test @MainActor func liveChangesUpdateInChatWithoutOpeningFullReview() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-live-code-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let file = project.appendingPathComponent("App.swift")
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    let session = store.chatSession
    session.sending = true
    let baseline = try await session.fileChangeTracker.snapshot(project)
    let replyID = UUID()
    let tracking = store.trackLiveFileChanges(in: session, baseline: baseline, replyID: replyID)
    defer { tracking.cancel() }
    try "first edit\n".write(to: file, atomically: true, encoding: .utf8)
    for _ in 0..<100 {
        if session.liveFileChanges != nil { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(session.sending)
    #expect(session.reviewedChanges == nil)
    #expect(session.fileChanges.isEmpty)
    #expect(session.liveFileChanges?.id == replyID)
    #expect(session.liveFileChanges?.files.first?.after == "first edit\n")
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    for _ in 0..<100 {
        if session.liveFileChanges == nil { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(session.liveFileChanges == nil)
    #expect(session.reviewedChanges == nil)
    try "second edit\n".write(to: file, atomically: true, encoding: .utf8)
    for _ in 0..<100 {
        if session.liveFileChanges?.files.first?.after == "second edit\n" { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(session.liveFileChanges?.files.first?.after == "second edit\n")
    #expect(session.reviewedChanges == nil)
    tracking.cancel()
    await tracking.value
    try "after cancellation\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(session.liveFileChanges?.files.first?.after == "second edit\n")
    session.sending = false
}

@Test @MainActor func fullFileReviewOpensOnlyWhenRequested() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-inline-review-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    let edit = FileEdit(path: "App.swift", before: "old", after: "new", permissions: nil, additions: 1, deletions: 1, diff: "-old\n+new")
    let changes = FileChangeSet(replyID: UUID(), folder: root, createdAt: .now, files: [edit])
    store.fileChanges = [changes]
    #expect(store.reviewedChanges == nil)
    store.reviewFileChanges(changes, path: edit.path)
    #expect(store.reviewedChanges == changes)
    #expect(store.reviewedFilePath == edit.path)
    store.reviewedChanges = nil
    #expect(store.fileChanges == [changes])
}
