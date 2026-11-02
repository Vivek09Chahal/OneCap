import Foundation
import Testing
@testable import OneCapCore

@Test func fileReviewLayoutPreservesNumbersMarkersAndMissingNewlines() {
    let file = FileEdit(path: "test.txt", before: "context\nold", after: "context\nnew", permissions: nil,
        additions: 1, deletions: 1, diff: "")
    let layout = FileReviewLayout(file: file)
    #expect(layout.hunks.count == 1)
    #expect(layout.rows.map(\.id) == Array(layout.rows.indices))
    let code = layout.rows.filter { !$0.isHeading }
    #expect(code.map(\.text) == ["context", "old", "new"])
    #expect(code.map(\.oldLine) == [1, 2, nil])
    #expect(code.map(\.newLine) == [1, nil, 2])
    #expect(code.map(\.marker) == [" ", "−", "+"])
    #expect(code.map(\.missingNewline) == [false, true, true])
}

@Test func fileReviewCacheKeepsOriginalRowsAcrossDecisionsAndExactBytes() async throws {
    var file = FileEdit(path: "test.txt", before: "", after: "é\n", permissions: nil,
        additions: 1, deletions: 0, diff: "")
    let cache = FileReviewLayoutCache()
    let original = try await cache.layout(for: file)
    file.hunkDecisions = [0: .rejected]
    let reviewed = try await cache.layout(for: file)
    #expect(original.rows.map(\.text) == reviewed.rows.map(\.text))
    let decomposed = FileEdit(path: file.path, before: "", after: "e\u{0301}\n", permissions: nil,
        additions: 1, deletions: 0, diff: "")
    let changed = try await cache.layout(for: decomposed)
    #expect(Array(changed.rows.last!.text.utf8) == Array("e\u{0301}".utf8))
}

@Test func fileReviewLayoutHandlesLargeChangesAndEmptyFiles() {
    let text = (0..<10_000).map { "line \($0)\n" }.joined()
    let file = FileEdit(path: "large.txt", before: nil, after: text, permissions: nil,
        additions: 10_000, deletions: 0, diff: "")
    let layout = FileReviewLayout(file: file)
    #expect(layout.rows.count == 10_001)
    #expect(layout.rows.last?.newLine == 10_000)
    let empty = FileEdit(path: "empty.txt", before: nil, after: "", permissions: nil,
        additions: 0, deletions: 0, diff: "")
    #expect(FileReviewLayout(file: empty).rows.last?.text == "Empty file added")
}
