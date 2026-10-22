import Foundation

enum ChatMarkdown {
    enum Block: Equatable {
        case prose(String)
        case code(String)
    }

    enum RenderedBlock: Sendable {
        case prose([Segment])
        case code(String)
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
        let result = RenderedMessage(blocks: blocks(source).map { block in
            switch block {
            case .prose(let text): .prose(segments(text))
            case .code(let text): .code(text)
            }
        })
        renderCache.messages.setObject(result, forKey: key, cost: max(1, source.utf8.count * 4))
        return result
    }

    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var buffer = ""
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
                    blocks.append(.code(buffer))
                    buffer = ""
                    fence = nil
                } else {
                    buffer += line + newline
                }
            } else if indentation <= 3, marker == "`" || marker == "~", length >= 3,
                      marker != "`" || !remainder.contains("`") {
                if !buffer.isEmpty { blocks.append(.prose(buffer)) }
                buffer = ""
                fence = marker
                fenceLength = length
            } else {
                buffer += line + newline
            }
        }
        if fence != nil { blocks.append(.code(buffer)) }
        else if !buffer.isEmpty { blocks.append(.prose(buffer)) }
        return blocks
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
