import Foundation
import Testing

@testable import OneCapCore

@Test func slashFileQueryOpensImmediatelyAndMatchesFromTheFirstCharacterAtTheCaret() throws {
    #expect(ProjectFileQuery.active(in: "/")?.text == "")
    #expect(ProjectFileQuery.active(in: "/a")?.text == "a")
    #expect(ProjectFileQuery.active(in: "/ap")?.text == "ap")
    #expect(ProjectFileQuery.active(in: "edit /App")?.text == "App")
    #expect(ProjectFileQuery.active(in: "edit /文件名")?.text == "文件名")
    #expect(ProjectFileQuery.active(in: "https://example.com/file") == nil)
    #expect(ProjectFileQuery.active(in: "normal/path") == nil)
    #expect(ProjectFileQuery.active(in: "/App ") == nil)
    let draft = "Review /App.swift and fix it"
    let caret = try #require(draft.range(of: "/App")?.upperBound)
    let query = try #require(ProjectFileQuery.active(in: draft, at: caret))
    #expect(query.text == "App")
    #expect(draft.replacingCharacters(in: query.range, with: "`Sources/App.swift`") == "Review `Sources/App.swift` and fix it")
}

@Test func projectFileSearchFindsNestedFilesAndSkipsDependenciesAndExternalLinks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-file-search-\(UUID())")
        .resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    for path in ["Sources/App.swift", "Tests/AppTests.swift", "Assets/Other.txt", "node_modules/HiddenApp.swift", ".git/HiddenApp.swift"] {
        let file = project.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Example source".write(to: file, atomically: true, encoding: .utf8)
    }
    let external = root.appendingPathComponent("ExternalApp.swift")
    try "Outside project".write(to: external, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("LinkedApp.swift"), withDestinationURL: external)
    try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("Cycle"), withDestinationURL: project)
    let reader = FolderDirectoryReader()
    #expect(try await reader.search("", in: project).isEmpty)
    #expect(try await reader.search("A", in: project).count == 3)
    #expect(try await reader.search("ap", in: project).count == 2)
    let matches = try await reader.search("APP", in: project)
    #expect(matches.map { $0.relativePath(in: project) } == ["Sources/App.swift", "Tests/AppTests.swift"])
    #expect(try await reader.search("Sources/App", in: project).count == 1)
    #expect(try await reader.search("missing", in: project).isEmpty)
    await #expect(throws: (any Error).self) {
        _ = try await ChatFileImporter().read([external], relativeTo: project)
    }
    await #expect(throws: (any Error).self) {
        _ = try await ChatFileImporter().read([project.appendingPathComponent("LinkedApp.swift")], relativeTo: project)
    }
}

@Test @MainActor func selectingAProjectFileUsesItsRelativePathAndPreservesAttachmentLimits() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-file-selection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("Sources/App.swift")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "let answer = 42".write(to: file, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    #expect(await store.attachFiles([file], relativeTo: root))
    #expect(store.draftAttachments.first?.name == "Sources/App.swift")
    #expect(ChatAttachment.context(store.draftAttachments).contains("let answer = 42"))
    #expect(try await ChatFileImporter().read([file]).first?.name == "App.swift")
    store.sending = true
    #expect(await store.attachFiles([file], relativeTo: root))
    store.removeAttachment(store.draftAttachments.last!.id)
    store.sending = false
    #expect(!(await store.attachFiles(Array(repeating: file, count: 5), relativeTo: root)))
    #expect(store.draftAttachments.count == 1)
}
