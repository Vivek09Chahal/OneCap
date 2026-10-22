import Foundation
import Testing

@testable import OneCapCore

@Test func chatMarkdownSeparatesVerticalCodeBlocksFromProse() {
    let flow = "Your app’s interface\n        ↕\nUser’s chosen harness\n        ↕\nModel provider"
    #expect(ChatMarkdown.blocks("Before\n```text\n" + flow + "\n```\nAfter") == [
        .prose("Before\n"), .code(flow), .prose("After")
    ])
    #expect(ChatMarkdown.blocks("~~~text\n" + flow) == [.code(flow)])
    #expect(String(ChatMarkdown.parse("`" + flow + "`").characters) == flow)
}

@Test func chatMarkdownKeepsHorizontalFlowsInline() {
    let flow = "Your message → harness → model requests search → answer"
    #expect(ChatMarkdown.blocks("`" + flow + "`") == [.prose("`" + flow + "`")])
    #expect(ChatMarkdown.blocks("```text\n" + flow + "\n```") == [.code(flow)])
    #expect(String(ChatMarkdown.parse("`" + flow + "`").characters) == flow)
}

@Test func chatMarkdownRendersBoldAndPreservesParagraphs() {
    let parsed = ChatMarkdown.parse("**Model:** generates responses.\n\n- **Harness:** runs tools.")
    #expect(String(parsed.characters) == "Model: generates responses.\n\n- Harness: runs tools.")
    let bold = parsed.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
    #expect(bold.map { String(parsed[$0.range].characters) } == ["Model:", "Harness:"])
}

@Test func chatMarkdownDisplaysActualURLOnceForAStyledLink() {
    let segments = ChatMarkdown.segments("Read [**official** documentation](https://example.com/docs).")
    let links = segments.filter { $0.link != nil }
    #expect(links.allSatisfy { $0.link?.absoluteString == "https://example.com/docs" })
    #expect(links.filter(\.startsLink).count == 1)
    #expect(links.map { String($0.text.characters) } == ["https://example.com/docs"])
    #expect(links.first?.text.link?.absoluteString == "https://example.com/docs")
    #expect(segments.map { String($0.text.characters) }.joined() == "Read https://example.com/docs.")
}

@Test func chatMarkdownLinksBareURLsButPreservesCodeAndEscapedAsterisks() {
    let source = "🌍 https://example.com/path and `https://example.com/code` and \\*\\*literal\\*\\*."
    let parsed = ChatMarkdown.parse(source)
    let links = parsed.runs.compactMap(\.link)
    #expect(links.map(\.absoluteString) == ["https://example.com/path"])
    #expect(String(parsed.characters).contains("**literal**"))
    #expect(parsed.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    #expect(ChatMarkdown.segments("[First](https://example.com) and [Second](https://example.com)").filter(\.startsLink).count == 2)
}


@Test func reopeningMessageReusesParsedMarkdownAndEditsUseFreshContent() throws {
    let source = "**Saved answer** with https://example.com/history\n```swift\nlet saved = true\n```"
    let first = ChatMarkdown.rendered(source)
    let reopened = ChatMarkdown.rendered(source)
    #expect(first === reopened)
    #expect(first.blocks.count == 2)
    guard case .prose(let prose) = first.blocks[0],
          case .code(let code, let language) = first.blocks[1] else {
        Issue.record("Expected parsed prose followed by a fenced code block")
        return
    }
    #expect(prose.contains { $0.link?.absoluteString == "https://example.com/history" })
    #expect(code == "let saved = true")
    #expect(language == "swift")
    let edited = ChatMarkdown.rendered(source + "\nUpdated answer")
    #expect(edited !== first)
    #expect(edited.blocks.count == 3)
    #expect(ChatMarkdown.rendered(source) === first)
}

@Test func responseMarkdownPreservesLanguageAndCodeInSingleLineAndStreamingFences() {
    for (source, expected, language) in [
        ("Before\n```swift\nlet name = \"Vivek\"\n```\nAfter", "let name = \"Vivek\"", "swift"),
        ("~~~css title=example\n@media (max-width: 600px) {\n  a { color: red; }\n}\n~~~", "@media (max-width: 600px) {\n  a { color: red; }\n}", "css"),
        ("```python\nprint('streaming')\n", "print('streaming')\n", "python"),
    ] {
        let rendered = ChatMarkdown.rendered(source)
        let codes = rendered.blocks.compactMap { block -> (String, String?)? in
            if case .code(let text, let language) = block { return (text, language) }
            return nil
        }
        #expect(codes.count == 1 && codes.first?.0 == expected && codes.first?.1 == language)
    }
    #expect(ChatMarkdown.rendered("`inline code`").blocks.count == 1)
    if case .prose(let segments) = ChatMarkdown.rendered("`inline code`").blocks[0] {
        #expect(segments.first?.text.runs.first?.inlinePresentationIntent?.contains(.code) == true)
    } else { Issue.record("Inline code should stay inside its paragraph") }
}

@Test func responseMarkdownSeparatesHeadingsParagraphsAndReadableListItems() {
    let rendered = ChatMarkdown.rendered("## Why use `Sendable`?\n\nFirst paragraph.\n\nSecond **paragraph**.\n\n- First item\n- `@media` — changes styles\n  - Nested item\n1. Ordered item\n\n> A note\n\n---")
    #expect(rendered.blocks.count == 9)
    if case .heading(let level, let text) = rendered.blocks[0] {
        #expect(level == 2 && text.map { String($0.text.characters) }.joined() == "Why use Sendable?")
    } else { Issue.record("Expected a styled heading") }
    if case .listItem(let marker, let depth, _) = rendered.blocks[5] {
        #expect(marker == "•" && depth == 1)
    } else { Issue.record("Expected a nested bullet") }
    if case .listItem(let marker, _, _) = rendered.blocks[6] {
        #expect(marker == "1.")
    } else { Issue.record("Expected the original ordered marker") }
    if case .quote = rendered.blocks[7] {} else { Issue.record("Expected a quote") }
    if case .divider = rendered.blocks[8] {} else { Issue.record("Expected a divider") }
}

@Test func standaloneBoldLabelsHaveParagraphSpacingEvenWithoutBlankLines() {
    let rendered = ChatMarkdown.rendered("Introductory text.\n**Example 2: A UI model**\nExplanation with `LegacyClient` and **emphasis**.\n__Another section__\nMore details.")
    let paragraphs = rendered.blocks.compactMap { block -> String? in
        if case .prose(let text) = block { return text.map { String($0.text.characters) }.joined() }
        return nil
    }
    #expect(paragraphs == ["Introductory text.", "Example 2: A UI model",
        "Explanation with LegacyClient and emphasis.", "Another section", "More details."])
    #expect(ChatMarkdown.rendered("**Bold** and regular **text**\ncontinues here.").blocks.count == 1)
}

@Test func consecutiveQuotedLinesStayTogetherAndSeparateFromSurroundingParagraphs() {
    let rendered = ChatMarkdown.rendered("This means:\n> First quoted line\n> continued on the next line\n>\n> Another quoted paragraph\nNormal text follows.")
    #expect(rendered.blocks.count == 3)
    if case .quote(let text) = rendered.blocks[1] {
        #expect(text.map { String($0.text.characters) }.joined()
            == "First quoted line\ncontinued on the next line\n\nAnother quoted paragraph")
    } else { Issue.record("Expected one grouped quote") }
}
