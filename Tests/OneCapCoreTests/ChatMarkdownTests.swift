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
