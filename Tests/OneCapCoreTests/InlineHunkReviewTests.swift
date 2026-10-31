import Foundation
import Testing
@testable import OneCapCore

@Test func hunkReviewKeepsStableRangesAndExactBytes() throws {
    for (before, after) in [
        ("a\nb\na\n", "a\na\nc\n"),
        ("one\r\nkeep\r\nlast", "ONE\r\nkeep\r\nLAST\n"),
        ("\u{e9}\nkeep\nend", "e\u{301}\nkeep\nEND"),
        ("first\nkeep\nlast\n", "keep\nnew\nlast\n"),
    ] {
        let diff = FileTextDiff.make(before: before, after: after)
        var edit = FileEdit(path: "file", before: before, after: after, permissions: nil,
            additions: diff.added, deletions: diff.removed, diff: diff.text)
        let ids = edit.hunks.map(\.id)
        edit.hunkDecisions = [:]
        for id in ids.reversed() { edit.hunkDecisions?[id] = .rejected }
        #expect(Data((edit.reviewedAfter ?? "").utf8) == Data(before.utf8))
        #expect(edit.hunks.map(\.id) == ids)
        for id in ids { edit.hunkDecisions?[id] = .accepted }
        #expect(Data((edit.reviewedAfter ?? "").utf8) == Data(after.utf8))
        let decoded = try JSONDecoder().decode(FileEdit.self, from: JSONEncoder().encode(edit))
        #expect(decoded == edit)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
        legacy.removeValue(forKey: "hunkDecisions")
        #expect(try JSONDecoder().decode(FileEdit.self, from: JSONSerialization.data(withJSONObject: legacy)).hunkDecisions == nil)
    }
}

@Test @MainActor func inlineHunkReviewPersistsRejectsIndependentlyAndIntegratesWithUndoAndManualEditing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-hunks-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let url = project.appendingPathComponent("file.swift")
    let before = "one\ncontext\nthree\n"
    let after = "ONE\ncontext\nTHREE\n"
    try before.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    let state = root.appendingPathComponent("State/state.json")
    let store = AppStore(stateURL: state)
    await store.load()
    let baseline = try await store.fileChangeTracker.snapshot(project)
    try after.write(to: url, atomically: true, encoding: .utf8)
    let changes = try #require(try await store.fileChangeTracker.changes(since: baseline, replyID: UUID()))
    #expect(changes.files[0].hunks.count == 2)
    store.messages = [.init(role: "user", text: "Edit the file")]
    store.fileChanges = [changes]
    await store.reviewHunk(0, decision: .rejected, path: "file.swift", changesID: changes.id)
    #expect(store.fileChangeError == nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "one\ncontext\nTHREE\n")
    await store.reviewHunk(1, decision: .accepted, path: "file.swift", changesID: changes.id)
    await store.historySaveTask?.value
    let reopened = AppStore(stateURL: state)
    await reopened.load()
    reopened.openConversation(store.conversationID)
    #expect(reopened.fileChanges[0].files[0].hunkDecisions == [0: .rejected, 1: .accepted])
    await reopened.restoreFileChanges(changes.id)
    #expect(reopened.fileChangeError == nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == before)
    await reopened.restoreFileChanges(changes.id)
    #expect(try String(contentsOf: url, encoding: .utf8) == "one\ncontext\nTHREE\n")
    await reopened.reviewHunk(0, decision: nil, path: "file.swift", changesID: changes.id)
    #expect(try String(contentsOf: url, encoding: .utf8) == after)
    await reopened.reviewHunk(0, decision: .rejected, path: "file.swift", changesID: changes.id)
    try await reopened.saveReviewedFile("manual\n", path: "file.swift", changesID: changes.id, expected: "one\ncontext\nTHREE\n")
    #expect(reopened.fileChanges[0].files[0].hunkDecisions == nil)
    await reopened.restoreFileChanges(changes.id)
    #expect(try String(contentsOf: url, encoding: .utf8) == before)
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    await reopened.historySaveTask?.value
}

@Test func hunkReviewHandlesFileExistenceAndProtectsNewerEdits() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-hunk-files-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let tracker = FileChangeTracker()
    let url = root.appendingPathComponent("file")
    for (before, after): (String?, String?) in [(nil, ""), ("", nil), (nil, "new\n"), ("old", nil)] {
        if let after { try Data(after.utf8).write(to: url) }
        else { try? FileManager.default.removeItem(at: url) }
        let diff = FileTextDiff.make(before: before, after: after)
        let edit = FileEdit(path: "file", before: before, after: after, permissions: nil,
            additions: diff.added, deletions: diff.removed, diff: diff.text)
        let rejected = try await tracker.reviewHunk(0, decision: .rejected, in: edit, folder: root)
        #expect(try await tracker.editableText(path: "file", folder: root) == before)
        _ = try await tracker.reviewHunk(0, decision: .accepted, in: rejected, folder: root)
        #expect(try await tracker.editableText(path: "file", folder: root) == after)
        try "newer".write(to: url, atomically: true, encoding: .utf8)
        for decision: HunkDecision? in [.accepted, .rejected, nil] {
            await #expect(throws: (any Error).self) {
                try await tracker.reviewHunk(0, decision: decision, in: edit, folder: root)
            }
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "newer")
        try FileManager.default.removeItem(at: url)
        let target = root.appendingPathComponent("target")
        try "safe".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        await #expect(throws: (any Error).self) { try await tracker.reviewHunk(0, decision: .rejected, in: edit, folder: root) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "safe")
        try FileManager.default.removeItem(at: url)
    }
}
