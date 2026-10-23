import Foundation
import Testing

@testable import OneCapCore

@Test func storageMeasuresOwnedFilesWithoutFollowingProjectLinks() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-storage-\(UUID())")
    let root = base.appendingPathComponent("Data")
    let app = base.appendingPathComponent("OneCap.app")
    let cache = base.appendingPathComponent("Cache")
    let preferences = base.appendingPathComponent("Preferences.plist")
    defer { try? FileManager.default.removeItem(at: base) }
    let files: [(String, AppStorageUsage.Category)] = [
        ("conversations.json", .chats), ("ChatWorkspaces/chat/.hidden", .workspaces),
        ("agents/tool/binary", .agents), ("runtimes/node", .agents),
        ("Skills/example/SKILL.md", .skills), ("skills.json", .skills), ("state.json", .other)
    ]
    var expected: [AppStorageUsage.Category: Int64] = [:]
    for (path, category) in files {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: 8192).write(to: file)
        expected[category, default: 0] += try allocatedSize(file)
    }
    for (file, category) in [(app.appendingPathComponent("Contents/MacOS/OneCap"), AppStorageUsage.Category.application),
                              (cache.appendingPathComponent("cache"), .other), (preferences, .other)] {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 66, count: 8192).write(to: file)
        expected[category, default: 0] += try allocatedSize(file)
    }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("ChatWorkspaces/project"),
                                              withDestinationURL: base)
    let reader = AppStorageReader(root: root, application: app, caches: cache, preferences: preferences)
    let usage = try await reader.measure()
    #expect(usage.bytes == expected)
    #expect(usage.total == expected.values.reduce(0, +))
    #expect(usage.unreadableItems == 0)
    #expect(usage.locations[.application] == [app])
    #expect(usage.locations[.agents] == [root.appendingPathComponent("agents"), root.appendingPathComponent("runtimes")])
    #expect(Set(usage.locations[.other, default: []].map { $0.resolvingSymlinksInPath() }) ==
        Set([cache, preferences, root.appendingPathComponent("state.json")].map { $0.resolvingSymlinksInPath() }))
    #expect(!usage.locations.values.flatMap { $0 }.contains(root.appendingPathComponent("ChatWorkspaces/project")))
    try FileManager.default.removeItem(at: root.appendingPathComponent("conversations.json"))
    let refreshed = try await reader.measure()
    #expect(refreshed.bytes[.chats, default: 0] == 0)
    #expect(refreshed.total == usage.total - expected[.chats, default: 0])
}

@Test func storageHandlesMissingDataOnFirstLaunch() async throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let usage = try await AppStorageReader(root: missing, application: nil,
        caches: missing, preferences: missing).measure()
    #expect(usage.total == 0)
    #expect(usage.unreadableItems == 0)
}

private func allocatedSize(_ file: URL) throws -> Int64 {
    let values = try file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
    return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
}
