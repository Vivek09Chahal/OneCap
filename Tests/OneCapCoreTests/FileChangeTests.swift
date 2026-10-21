import Foundation
import Testing

@testable import OneCapCore

private func changeTestRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-changes-\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func turnSnapshotTracksAddedModifiedDeletedAndEmptyFilesAndUndoPreservesPriorWork() async throws {
    let root = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try "existing uncommitted work\n".write(to: root.appendingPathComponent("Existing.swift"), atomically: true, encoding: .utf8)
    try "delete me\n".write(to: root.appendingPathComponent("Deleted.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Existing.swift").path)
    let tracker = FileChangeTracker()
    let before = try await tracker.snapshot(root)
    #expect(try await tracker.changes(since: before, replyID: UUID()) == nil)
    try "existing uncommitted work\nnew line\n".write(to: root.appendingPathComponent("Existing.swift"), atomically: true, encoding: .utf8)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Deleted.txt"))
    try "new file\n".write(to: root.appendingPathComponent("Added.txt"), atomically: true, encoding: .utf8)
    try Data().write(to: root.appendingPathComponent("Empty.txt"))
    let changes = try #require(try await tracker.changes(since: before, replyID: UUID()))
    #expect(Set(changes.files.map(\.path)) == ["Existing.swift", "Deleted.txt", "Added.txt", "Empty.txt"])
    #expect(changes.additions == 2 && changes.deletions == 1)
    #expect(changes.files.first { $0.path == "Existing.swift" }?.before == "existing uncommitted work\n")
    try await tracker.undo(changes)
    #expect(try String(contentsOf: root.appendingPathComponent("Existing.swift"), encoding: .utf8) == "existing uncommitted work\n")
    #expect(try String(contentsOf: root.appendingPathComponent("Deleted.txt"), encoding: .utf8) == "delete me\n")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Added.txt").path))
    let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("Existing.swift").path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o755)
    try await tracker.reapply(changes)
    #expect(try String(contentsOf: root.appendingPathComponent("Existing.swift"), encoding: .utf8) == "existing uncommitted work\nnew line\n")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Deleted.txt").path))
    #expect(try String(contentsOf: root.appendingPathComponent("Added.txt"), encoding: .utf8) == "new file\n")
    #expect(try Data(contentsOf: root.appendingPathComponent("Empty.txt")).isEmpty)
}

@Test func undoRefusesNewerChangesBeforeRestoringAnyFile() async throws {
    let root = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let tracker = FileChangeTracker()
    let before = try await tracker.snapshot(root)
    for name in ["A.txt", "B.txt"] { try "agent".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    let changes = try #require(try await tracker.changes(since: before, replyID: UUID()))
    try "my newer edit".write(to: root.appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await tracker.undo(changes) }
    #expect(try String(contentsOf: root.appendingPathComponent("A.txt"), encoding: .utf8) == "agent")
    #expect(try String(contentsOf: root.appendingPathComponent("B.txt"), encoding: .utf8) == "my newer edit")
}

@Test func snapshotsExcludeDependenciesLinksAndUnsupportedFilesWithoutReportingFalseDeletions() async throws {
    let root = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let tracker = FileChangeTracker()
    let file = root.appendingPathComponent("Text.txt")
    try "text".write(to: file, atomically: true, encoding: .utf8)
    let before = try await tracker.snapshot(root)
    try Data(repeating: 65, count: 600_000).write(to: file)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    try "generated".write(to: root.appendingPathComponent("node_modules/index.js"), atomically: true, encoding: .utf8)
    try Data([0, 255]).write(to: root.appendingPathComponent("Binary.bin"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
    #expect(try await tracker.changes(since: before, replyID: UUID()) == nil)
}

@Test func reapplyRefusesNewerEditsBeforeChangingAnyFile() async throws {
    let root = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let tracker = FileChangeTracker()
    for name in ["A.txt", "B.txt"] {
        try "original".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let before = try await tracker.snapshot(root)
    for name in ["A.txt", "B.txt"] {
        try "agent edit".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let changes = try #require(try await tracker.changes(since: before, replyID: UUID()))
    try await tracker.undo(changes)
    try "newer user edit".write(to: root.appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await tracker.reapply(changes) }
    #expect(try String(contentsOf: root.appendingPathComponent("A.txt"), encoding: .utf8) == "original")
    #expect(try String(contentsOf: root.appendingPathComponent("B.txt"), encoding: .utf8) == "newer user edit")
}

@Test func undoRejectsSymlinkedParentsAndTraversal() async throws {
    let root = try changeTestRoot()
    let outside = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    let folder = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "old".write(to: folder.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    let tracker = FileChangeTracker()
    let before = try await tracker.snapshot(root)
    try "new".write(to: folder.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    let changes = try #require(try await tracker.changes(since: before, replyID: UUID()))
    try FileManager.default.removeItem(at: folder)
    try "new".write(to: outside.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
    await #expect(throws: (any Error).self) { try await tracker.undo(changes) }
    #expect(try String(contentsOf: outside.appendingPathComponent("App.swift"), encoding: .utf8) == "new")
    let invalid = FileChangeSet(replyID: UUID(), folder: root, createdAt: .now, files: [
        FileEdit(path: "../escape", before: "old", after: nil, permissions: nil, additions: 0, deletions: 0, diff: "")])
    await #expect(throws: (any Error).self) { try await tracker.undo(invalid) }
}

@Test func lineDiffHandlesRepeatedLinesAndFinalNewlineChanges() {
    let repeated = FileTextDiff.make(before: "a\nb\na\n", after: "a\na\nc\n")
    #expect(repeated.added == 1 && repeated.removed == 1)
    #expect(repeated.text.contains("-b") && repeated.text.contains("+c"))
    let newline = FileTextDiff.make(before: "a", after: "a\n")
    #expect(newline.added == 1 && newline.removed == 1)
    #expect(newline.text.contains("No newline at end of file"))
    let crlf = FileTextDiff.make(before: "a\r\nb\r\n", after: "a\r\nc\r\n")
    #expect(crlf.added == 1 && crlf.removed == 1)
    let normalization = FileTextDiff.make(before: "\u{00e9}\n", after: "e\u{0301}\n")
    #expect(normalization.added == 1 && normalization.removed == 1)
}

@Test @MainActor func agentEditsAppearAfterReplyPersistPerChatAndCanBeUndoneAfterReopening() async throws {
    let root = try changeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let source = project.appendingPathComponent("App.swift")
    try "before\n".write(to: source, atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json,sys,pathlib
    def send(o): print(json.dumps(dict(jsonrpc='2.0',**o)),flush=True)
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); result={}
        if method=='initialize': result=dict(protocolVersion=1)
        elif method=='session/new': result=dict(sessionId='edits')
        elif method=='session/prompt':
            if 'fail' in m['params']['prompt'][-1]['text'].lower():
                pathlib.Path(sys.argv[1]).write_text('partial edit\n')
                send(dict(id=m['id'],error=dict(code=-32603,message='Tool failed after editing')))
                continue
            pathlib.Path(sys.argv[1]).write_text('after\nadded\n')
            send(dict(method='session/update',params=dict(sessionId='edits',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='Updated the file.')))))
        send(dict(id=m['id'],result=result))
    """#.write(to: script, atomically: true, encoding: .utf8)
    let stateURL = root.appendingPathComponent("state.json")
    let store = AppStore(stateURL: stateURL)
    await store.load()
    let agent = InstalledAgent(id: "edit-fixture", name: "Edit fixture", version: "1", executable: "/usr/bin/python3", arguments: ["-u", script.path, source.path], environment: [:], directory: root.path)
    store.installed = [agent]
    store.selectedAgentID = agent.id
    store.chatUsesAgent = true
    store.workspace = project
    await store.connect()
    store.send("Edit the file", useAgent: true)
    for _ in 0..<500 {
        if !store.sending { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!store.sending)
    let changes = try #require(store.fileChanges.first)
    #expect(changes.files.map(\.path) == ["App.swift"])
    #expect(changes.additions == 2 && changes.deletions == 1)
    #expect(store.messages.last?.changeSetID == changes.id)
    let chat = store.conversationID
    await store.historySaveTask?.value
    store.resetChat()
    #expect(store.fileChanges.isEmpty)
    store.openConversation(chat)
    #expect(store.fileChanges.first?.id == changes.id)
    await store.restoreFileChanges(changes.id)
    #expect(store.fileChangeError == nil)
    #expect(store.fileChanges.first?.revertedAt != nil)
    #expect(try String(contentsOf: source, encoding: .utf8) == "before\n")
    await store.historySaveTask?.value
    let reopened = AppStore(stateURL: stateURL)
    await reopened.load()
    reopened.openConversation(chat)
    #expect(reopened.fileChanges.first?.revertedAt != nil)
    #expect(reopened.messages.last?.changeSetID == changes.id)
    await reopened.restoreFileChanges(changes.id)
    #expect(reopened.fileChangeError == nil && reopened.fileChanges.first?.revertedAt == nil)
    #expect(try String(contentsOf: source, encoding: .utf8) == "after\nadded\n")
    await reopened.historySaveTask?.value
    let reapplied = try await ConversationRepository(url: root.appendingPathComponent("conversations.json")).load()
    #expect(reapplied.first(where: { $0.id == chat })?.fileChanges?.first?.revertedAt == nil)
    await reopened.restoreFileChanges(changes.id)
    #expect(reopened.fileChanges.first?.revertedAt != nil)
    await store.connect()
    store.send("Fail after editing", useAgent: true)
    for _ in 0..<500 {
        if !store.sending { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.fileChanges.count == 2)
    #expect(store.messages.last?.replyState == .failed)
    #expect(store.messages.last?.changeSetID == store.fileChanges.last?.id)
    #expect(store.messages.last?.hasContent == true)
    await store.historySaveTask?.value
    await store.projectSaveTask?.value
    await reopened.historySaveTask?.value
    await reopened.projectSaveTask?.value
}
