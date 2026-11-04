import Foundation
import Observation
import Synchronization
import Testing

@testable import OneCapCore

@Test @MainActor func unchangedFileRefreshPreservesExpansionWithoutPublishingNewRows() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "hello".write(to: folder.appendingPathComponent("hello.swift"), atomically: true, encoding: .utf8)
    let tree = FolderTreeModel()
    await tree.open(root)
    await tree.toggle(try #require(tree.children[root]?.first))
    let rows = tree.rows.map(\.id)
    let changed = Mutex(false)
    withObservationTracking {
        _ = tree.children
        _ = tree.expanded
        _ = tree.errors
    } onChange: { changed.withLock { $0 = true } }
    await tree.open(root)
    #expect(!changed.withLock { $0 })
    #expect(tree.rows.map(\.id) == rows)
    #expect(tree.expanded.contains(folder))
    #expect(!tree.refreshing)
}

@Test @MainActor func fileRefreshUpdatesNestedAndCollapsedCachesAndPrunesDeletedBranches() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Sources", isDirectory: true)
    let nested = folder.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let tree = FolderTreeModel()
    await tree.open(root)
    let entry = try #require(tree.children[root]?.first)
    await tree.toggle(entry)
    await tree.toggle(try #require(tree.children[folder]?.first))
    await tree.toggle(entry) // Keep a collapsed directory's cached children fresh too.
    let newFile = nested.appendingPathComponent("new.swift")
    try "new".write(to: newFile, atomically: true, encoding: .utf8)
    await tree.refresh()
    #expect(tree.children[nested]?.map(\.url) == [newFile])
    #expect(!tree.expanded.contains(folder))
    await tree.toggle(entry)
    #expect(tree.rows.contains { $0.id == newFile })
    try FileManager.default.removeItem(at: nested)
    await tree.refresh()
    #expect(tree.expanded.contains(folder))
    #expect(!tree.expanded.contains(nested))
    #expect(tree.children[nested] == nil)
    #expect(!tree.rows.contains { $0.id == newFile })
}

@Test @MainActor func cancelledFolderLoadClearsItsLoadingStateAndCanRetry() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.swift")
    try "text".write(to: file, atomically: true, encoding: .utf8)
    let tree = FolderTreeModel()
    let load = Task { await tree.open(root) }
    load.cancel()
    await load.value
    #expect(tree.loading.isEmpty)
    await tree.open(root)
    #expect(tree.rows.map(\.id) == [file])
    #expect(!tree.refreshing)
}

@Test @MainActor func folderRefreshRecoversFromAnUnreadableRootAndSwitchesProjects() async throws {
    let parent = try treeFixture()
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appendingPathComponent("missing", isDirectory: true)
    let tree = FolderTreeModel()
    await tree.open(root)
    #expect(tree.errors[root] != nil)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    await tree.refresh()
    #expect(tree.errors.isEmpty)
    await tree.open(parent)
    #expect(tree.root == parent)
    #expect(tree.rows.map(\.id) == [root])
    #expect(tree.expanded.isEmpty)
}

@Test @MainActor func replacementFolderRefreshFinishesAfterThePreviousReadIsCancelled() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let tree = FolderTreeModel()
    await tree.open(root)
    let previous = Task { await tree.refresh() }
    await Task.yield()
    previous.cancel()
    let file = root.appendingPathComponent("latest.swift")
    try "latest".write(to: file, atomically: true, encoding: .utf8)
    await tree.open(root)
    await previous.value
    #expect(tree.rows.map(\.id) == [file])
    #expect(tree.loading.isEmpty)
    #expect(!tree.refreshing)
}

private func treeFixture() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("OneCap-tree-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test @MainActor func directoryFilterPreservesParentsAndHidesWholeHiddenBranches() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["Sources", ".hidden"] {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("Match.swift"))
    }
    let tree = FolderTreeModel()
    await tree.open(root)
    for entry in tree.children[root] ?? [] { await tree.toggle(entry) }
    tree.collapseAll()
    #expect(tree.expanded.isEmpty)
    #expect(tree.visibleRows(query: "Match", showHidden: false).map(\.entry.name) == ["Sources", "Match.swift"])
    #expect(tree.visibleRows(query: "Match", showHidden: true).count == 4)
    #expect(tree.visibleRows(query: "", showHidden: false).map(\.entry.name) == ["Sources"])
    #expect(tree.visibleRows(query: "missing", showHidden: true).isEmpty)
}

@Test func directoryGitStatusReadsBranchAndCountsUntrackedFiles() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = ProcessRunner()
    _ = try await runner.run("/usr/bin/git", ["-C", root.path, "init", "--initial-branch=directory-test"])
    try Data().write(to: root.appendingPathComponent("README.md"))
    try Data().write(to: root.appendingPathComponent("a file\nwith newline.swift"))
    let status = try #require(await WorkspaceGitStatus.read(in: root))
    #expect(status.branch == "directory-test")
    #expect(status.modified == 2)
    #expect(status.ahead == 0 && status.behind == 0)
    let nonRepository = root.deletingLastPathComponent()
    #expect(await WorkspaceGitStatus.read(in: nonRepository) == nil)
}

@Test func directoryGitChangesIncludeStagedUnstagedDeletedRenamedAndNestedFiles() async throws {
    let root = try treeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = ProcessRunner()
    func git(_ arguments: [String]) async throws {
        _ = try await runner.run("/usr/bin/git", ["-C", root.path] + arguments)
    }
    try await git(["init", "--initial-branch=test"])
    let sources = root.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    for name in ["edit.swift", "delete.swift", "rename.swift", "staged.swift"] {
        try "original\n".write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    try await git(["add", "."])
    try await git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial"])
    try "changed\n".write(to: sources.appendingPathComponent("edit.swift"), atomically: true, encoding: .utf8)
    try "staged\n".write(to: sources.appendingPathComponent("staged.swift"), atomically: true, encoding: .utf8)
    try await git(["add", "Sources/staged.swift"])
    try FileManager.default.removeItem(at: sources.appendingPathComponent("delete.swift"))
    try await git(["mv", "Sources/rename.swift", "Sources/renamed file.swift"])
    let unusualName = sources.appendingPathComponent("new file\nwith newline.swift")
    try Data().write(to: unusualName)
    try Data().write(to: root.appendingPathComponent("outside.txt"))
    let status = try #require(await WorkspaceGitStatus.read(in: root))
    #expect(status.modified == 6)
    #expect(status.changes[sources.appendingPathComponent("edit.swift")] == .modified)
    #expect(status.changes[sources.appendingPathComponent("staged.swift")] == .modified)
    #expect(status.changes[sources.appendingPathComponent("delete.swift")] == .deleted)
    #expect(status.changes[sources.appendingPathComponent("renamed file.swift")] == .renamed)
    #expect(status.changes[unusualName] == .added)
    #expect(status.directories.contains(sources))
    let nested = try #require(await WorkspaceGitStatus.read(in: sources))
    #expect(nested.modified == 5)
    #expect(nested.changes[unusualName] == .added)
    // A later read must remove indicators after changes disappear.
    try await git(["add", "."])
    try await git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "changes"])
    let clean = try #require(await WorkspaceGitStatus.read(in: root))
    #expect(clean.changes.isEmpty && clean.directories.isEmpty)
}
