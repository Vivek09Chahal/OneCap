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
