import AppKit
import Foundation
import Testing

@testable import OneCapCore

@Test func editableFileColorsUseTheSameLanguageMappingAsDiffs() async throws {
    for (path, source) in [
        ("Example.swift", "\nimport Foundation\nlet café = \"🌍\"\n"),
        ("component.tsx", "const count: number = 42;\n"),
        ("script.zsh", "#!/bin/zsh\necho \"hello\"\n"),
        ("Dockerfile", "FROM alpine:latest\nRUN echo hello\n"),
        ("notes.unknown-format", "\tplain & <text>\n"),
    ] {
        for dark in [false, true] {
            let colored = try await FileSyntaxHighlighter.shared.code(source, path: path, dark: dark)
            #expect(String(colored.characters) == source)
            if !path.hasSuffix("unknown-format") {
                #expect(Set(colored.runs.compactMap { $0.appKit.foregroundColor }).count >= 2)
            }
        }
    }
}

@Test func responseCodeColorsSwiftAndCSSAndPreservesWhitespaceInBothThemes() async throws {
    for language in ["swift", "css", "unknown-language"] {
        let source = language == "swift" ? "\n  class UserManager {\n    var name = \"Vivek\"\n  }\n"
            : "  @media (max-width: 600px) {\n    .container { width: 100%; }\n  }\n"
        var colors: [Set<NSColor>] = []
        for dark in [false, true] {
            let highlighted = try await FileSyntaxHighlighter.shared.code(source, language: language, dark: dark)
            #expect(String(highlighted.characters) == source)
            colors.append(Set(highlighted.runs.compactMap { $0.appKit.foregroundColor }))
            let reopened = try await FileSyntaxHighlighter.shared.code(source, language: language, dark: dark)
            #expect(reopened == highlighted)
        }
        if language != "unknown-language" {
            #expect(colors.allSatisfy { $0.count >= 2 })
            #expect(colors[0] != colors[1])
        }
    }
}

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
