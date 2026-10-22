import Foundation

enum ChatMarkdown {
    enum Block: Equatable {
        case prose(String)
        case code(String)
    }

    enum RenderedBlock: Sendable {
        case prose([Segment])
        case heading(level: Int, text: [Segment])
        case listItem(marker: String, depth: Int, text: [Segment])
        case quote([Segment])
        case divider
        case code(String, language: String?)

        var isListItem: Bool {
            if case .listItem = self { return true }
            return false
        }
    }

    final class RenderedMessage: NSObject, Sendable {
        let blocks: [RenderedBlock]

        init(blocks: [RenderedBlock]) { self.blocks = blocks }
    }

    // NSCache is thread-safe and can discard parsed messages under memory
    // pressure. Keep theme colors out of this cache so appearance stays live.
    private final class RenderCache: @unchecked Sendable {
        let messages = NSCache<NSString, RenderedMessage>()

        init() {
            messages.countLimit = 256
            messages.totalCostLimit = 4 * 1024 * 1024
        }
    }

    private static let renderCache = RenderCache()

    static func rendered(_ source: String) -> RenderedMessage {
        let key = source as NSString
        if let cached = renderCache.messages.object(forKey: key) { return cached }
        let result = RenderedMessage(blocks: fencedBlocks(source).flatMap { item -> [RenderedBlock] in
            switch item.block {
            case .prose(let text): proseBlocks(text)
            case .code(let text): [.code(text, language: item.language)]
            }
        })
        renderCache.messages.setObject(result, forKey: key, cost: max(1, source.utf8.count * 4))
        return result
    }

    static func blocks(_ source: String) -> [Block] {
        fencedBlocks(source).map(\.block)
    }

    private static func fencedBlocks(_ source: String) -> [(block: Block, language: String?)] {
        var blocks: [(block: Block, language: String?)] = []
        var buffer = ""
        var language: String?
        var fence: Character?
        var fenceLength = 0
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let indentation = line.prefix(while: { $0 == " " }).count
            let trimmed = line.dropFirst(indentation)
            let marker = trimmed.first
            let length = trimmed.prefix(while: { $0 == marker }).count
            let remainder = trimmed.dropFirst(length)
            let newline = index < lines.count - 1 ? "\n" : ""
            if let currentFence = fence {
                if indentation <= 3, marker == currentFence, length >= fenceLength,
                   remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                    if buffer.hasSuffix("\n") { buffer.removeLast() }
                    blocks.append((.code(buffer), language))
                    buffer = ""
                    fence = nil
                } else {
                    buffer += line + newline
                }
            } else if indentation <= 3, marker == "`" || marker == "~", length >= 3,
                      marker != "`" || !remainder.contains("`") {
                if !buffer.isEmpty { blocks.append((.prose(buffer), nil)) }
                buffer = ""
                fence = marker
                fenceLength = length
                language = remainder.split(whereSeparator: \.isWhitespace).first.map(String.init)
            } else {
                buffer += line + newline
            }
        }
        if fence != nil { blocks.append((.code(buffer), language)) }
        else if !buffer.isEmpty { blocks.append((.prose(buffer), nil)) }
        return blocks
    }

    private static let listPattern = try! NSRegularExpression(pattern: #"^( *)([-+*]|[0-9]{1,9}[.)])\s+(.+)$"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})\s+(.+)$"#)

    private static func proseBlocks(_ source: String) -> [RenderedBlock] {
        var result: [RenderedBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        func flush() {
            if !paragraph.isEmpty { result.append(.prose(segments(paragraph.joined(separator: "\n")))) }
            paragraph = []
        }
        func flushQuote() {
            if !quote.isEmpty { result.append(.quote(segments(quote.joined(separator: "\n")))) }
            quote = []
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            let text = line as NSString
            if !trimmed.hasPrefix("> ") && trimmed != ">" { flushQuote() }
            if trimmed.isEmpty { flush() }
            else if let match = headingPattern.firstMatch(in: line, range: range) {
                flush()
                let title = text.substring(with: match.range(at: 2)).replacingOccurrences(
                    of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
                result.append(.heading(level: match.range(at: 1).length, text: segments(title)))
            } else if let match = listPattern.firstMatch(in: line, range: range) {
                flush()
                let marker = text.substring(with: match.range(at: 2))
                result.append(.listItem(marker: ["-", "+", "*"].contains(marker) ? "•" : marker,
                    depth: match.range(at: 1).length / 2, text: segments(text.substring(with: match.range(at: 3)))))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flush()
                result.append(.divider)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flush()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if isStandaloneLabel(trimmed) {
                flush()
                result.append(.prose(segments(trimmed)))
            } else { paragraph.append(line) }
        }
        flushQuote()
        flush()
        return result
    }

    private static func isStandaloneLabel(_ line: String) -> Bool {
        guard (line.hasPrefix("**") && line.hasSuffix("**"))
                || (line.hasPrefix("__") && line.hasSuffix("__")) else { return false }
        let text = parse(line)
        return !text.characters.isEmpty && text.runs.allSatisfy {
            $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
    }

    struct Segment: Sendable {
        let text: AttributedString
        let link: URL?
        let startsLink: Bool
    }

    static func parse(_ source: String) -> AttributedString {
        var text = (try? AttributedString(markdown: source, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            appliesSourcePositionAttributes: true))) ?? AttributedString(source)

        // Foundation drops inline emphasis inside link labels. Parse each label
        // separately and retain the destination and any surrounding emphasis.
        var styled = AttributedString()
        for run in text.runs {
            let original = AttributedString(text[run.range])
            if run.inlinePresentationIntent?.contains(.code) == true,
               let position = run.markdownSourcePosition,
               let range = Range<String.Index>(position, in: source), source[range].contains("\n") {
                var code = AttributedString(String(source[range]))
                code.mergeAttributes(run.attributes)
                styled.append(code)
            } else if run.link != nil, let position = run.markdownSourcePosition,
               let range = Range<String.Index>(position, in: source),
               var label = try? AttributedString(markdown: String(source[range]), options: .init(
                   interpretedSyntax: .inlineOnlyPreservingWhitespace)),
               String(label.characters) == String(original.characters) {
                if let surrounding = run.inlinePresentationIntent {
                    for inner in Array(label.runs) {
                        label[inner.range].inlinePresentationIntent =
                            (inner.inlinePresentationIntent ?? []).union(surrounding)
                    }
                }
                label.mergeAttributes(run.attributes, mergePolicy: .keepCurrent)
                styled.append(label)
            } else {
                styled.append(original)
            }
        }
        text = styled

        // Markdown links already have destinations. Also recognize pasted URLs,
        // without turning URLs inside inline code into links.
        let plain = String(text.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = match.url, let range = Range(match.range, in: plain),
                      let lower = AttributedString.Index(range.lowerBound, within: text),
                      let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
                let bounds = lower..<upper
                guard text[bounds].runs.allSatisfy({
                    $0.link == nil && $0.inlinePresentationIntent?.contains(.code) != true
                }) else { continue }
                text[bounds].link = url
            }
        }
        return text
    }

    static func segments(_ source: String) -> [Segment] {
        let text = parse(source)
        var previousLink: URL?
        return text.runs.compactMap { run in
            let startsLink = run.link != nil && run.link != previousLink
            let continuesLink = run.link != nil && run.link == previousLink
            previousLink = run.link
            if continuesLink { return nil }
            var content = AttributedString(text[run.range])
            if let url = run.link {
                content = AttributedString(url.absoluteString)
                content.link = url
            }
            return Segment(text: content, link: run.link, startsLink: startsLink)
        }
    }
}
