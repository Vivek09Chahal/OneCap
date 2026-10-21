import AppKit
import Foundation
import Testing

@testable import OneCapCore

@Test func syntaxColorsPreserveDiffTextAndMultilineCommentsInBothThemes() async throws {
    let before = "\n  import Foundation\n/* A comment\ncontinued here\n*/\nlet café = \"🌍 & <tag>\"\n"
    let after = before.replacingOccurrences(of: "<tag>", with: "<updated>")
    let diff = FileTextDiff.make(before: before, after: after)
    let file = FileEdit(path: "Example.swift", before: before, after: after,
        permissions: nil, additions: diff.added, deletions: diff.removed, diff: diff.text)
    var themeColors: [Set<NSColor>] = []
    for dark in [false, true] {
        let lines = try await FileSyntaxHighlighter.shared.lines(for: file, dark: dark)
        #expect(lines.map { String($0.characters) } == diff.text.components(separatedBy: "\n"))
        let colors = Set(lines.flatMap { $0.runs.compactMap { $0.appKit.foregroundColor } })
        #expect(colors.count >= 3)
        themeColors.append(colors)
        let comment = try #require(lines.first { String($0.characters).contains("continued here") })
        #expect(comment.runs.contains { $0.appKit.foregroundColor != nil })
    }
    #expect(themeColors[0] != themeColors[1])
}

@Test func syntaxHighlightingHandlesOtherLanguagesUnknownExtensionsAndWhitespace() async throws {
    for (path, source) in [
        ("app.py", "def hello():\n    return \"Hello\"\n"),
        ("app.tsx", "const value: number = 42;\n"),
        ("data.json", "{\"enabled\": true, \"count\": 42}"),
        ("readme.unknown-format", "\tplain & <text>\r\n"),
        ("Empty.swift", ""),
        ("Spaces.swift", " \t\n\n"),
    ] {
        let diff = FileTextDiff.make(before: nil, after: source)
        let file = FileEdit(path: path, before: nil, after: source, permissions: nil,
            additions: diff.added, deletions: diff.removed, diff: diff.text)
        let lines = try await FileSyntaxHighlighter.shared.lines(for: file, dark: true)
        #expect(lines.map { String($0.characters) } == diff.text.components(separatedBy: "\n"))
        if ["py", "tsx", "json"].contains(URL(fileURLWithPath: path).pathExtension) {
            #expect(lines.contains { $0.runs.contains { $0.appKit.foregroundColor != nil } })
        }
    }
}
