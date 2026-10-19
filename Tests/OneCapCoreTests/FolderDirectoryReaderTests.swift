import Foundation
import Testing

@testable import OneCapCore

@Test func folderTreeReadsOneLevelWithFoldersFirstAndDoesNotExpandSymlinks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-tree-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sources = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try Data().write(to: sources.appendingPathComponent("Nested.swift"))
    for name in ["File10.swift", "File2.swift", ".gitignore"] {
        try Data().write(to: root.appendingPathComponent(name))
    }
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Loop"), withDestinationURL: root)
    let reader = FolderDirectoryReader()
    let entries = try await reader.contents(of: root)
    #expect(entries.first?.name == "Sources")
    #expect(entries.first?.canExpand == true)
    #expect(!entries.contains { $0.name == "Nested.swift" })
    #expect(entries.contains { $0.name == ".gitignore" })
    #expect(entries.filter { $0.name.hasPrefix("File") }.map(\.name) == ["File2.swift", "File10.swift"])
    let link = try #require(entries.first { $0.name == "Loop" })
    #expect(link.isSymbolicLink)
    #expect(!link.canExpand)
    let nested = try await reader.contents(of: sources)
    #expect(nested.map(\.name) == ["Nested.swift"])
    await #expect(throws: (any Error).self) {
        try await reader.contents(of: root.appendingPathComponent("Missing"))
    }
}
