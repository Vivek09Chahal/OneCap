import Foundation
import Observation
import Synchronization
import Testing

@testable import OneCapCore

@Test @MainActor func inlineFileEditsUpdateDiskDiffHistoryAndUndoWithoutAnExternalEditor() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-inline-edit-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let file = project.appendingPathComponent("App.swift")
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    let store = AppStore(stateURL: root.appendingPathComponent("State/state.json"))
    await store.load()
    let baseline = try await store.fileChangeTracker.snapshot(project)
    try "agent\n".write(to: file, atomically: true, encoding: .utf8)
    let reply = ChatMessage(role: "assistant", text: "Updated")
    let changes = try #require(try await store.fileChangeTracker.changes(since: baseline, replyID: reply.id))
    store.messages = [.init(role: "user", text: "Edit"), reply]
    store.fileChanges = [changes]
    store.reviewFileChanges(changes)
    let invalidatedSurroundingUI = Mutex(false)
    withObservationTracking {
        _ = store.applyingFileUndo
        _ = store.reviewedChanges
        _ = store.fileTreeRevision
    } onChange: {
        invalidatedSurroundingUI.withLock { $0 = true }
    }
    #expect(try await store.fileChangeTracker.editableText(path: "App.swift", folder: project) == "agent\n")
    try await store.saveReviewedFile("manual\nextra\n", path: "App.swift", changesID: changes.id, expected: "agent\n")
    #expect(try String(contentsOf: file, encoding: .utf8) == "manual\nextra\n")
    #expect(store.fileChanges.first?.files.first?.before == "original\n")
    #expect(store.fileChanges.first?.files.first?.after == "manual\nextra\n")
    #expect(store.fileChanges.first?.additions == 2)
    #expect(!invalidatedSurroundingUI.withLock { $0 })
    #expect(!store.savingReviewedFile)
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    await store.historySaveTask?.value
    let reopened = AppStore(stateURL: root.appendingPathComponent("State/state.json"))
    await reopened.load()
    reopened.openConversation(store.conversationID)
    #expect(reopened.fileChanges.first?.files.first?.after == "manual\nextra\n")
    await reopened.restoreFileChanges(changes.id)
    #expect(reopened.fileChangeError == nil)
    #expect(try String(contentsOf: file, encoding: .utf8) == "original\n")
    await reopened.restoreFileChanges(changes.id)
    #expect(try String(contentsOf: file, encoding: .utf8) == "manual\nextra\n")
    await reopened.historySaveTask?.value
}

@Test func inlineSavingPreservesNewerEditsAndRejectsTraversalLinksBinaryAndOversizeFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-safe-edit-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    let tracker = FileChangeTracker()
    try "newer".write(to: file, atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await tracker.saveText("draft", path: "file.txt", folder: root, expected: "old") }
    #expect(try String(contentsOf: file, encoding: .utf8) == "newer")
    await #expect(throws: (any Error).self) { try await tracker.saveText("draft", path: "../escape.txt", folder: root, expected: nil) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: file)
    await #expect(throws: (any Error).self) { try await tracker.saveText("draft", path: "link.txt", folder: root, expected: "newer") }
    await #expect(throws: (any Error).self) { try await tracker.saveText("\0", path: "file.txt", folder: root, expected: "newer") }
    await #expect(throws: (any Error).self) {
        try await tracker.saveText(String(repeating: "x", count: 512 * 1024 + 1), path: "file.txt", folder: root, expected: "newer")
    }
    #expect(try await tracker.editableText(path: "new.txt", folder: root) == nil)
    try await tracker.saveText("created", path: "new.txt", folder: root, expected: nil)
    #expect(try await tracker.editableText(path: "new.txt", folder: root) == "created")
    try Data([0, 255]).write(to: file)
    await #expect(throws: (any Error).self) { try await tracker.editableText(path: "file.txt", folder: root) }
}
