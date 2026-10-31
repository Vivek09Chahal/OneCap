import AppKit
import CoreText
import UniformTypeIdentifiers

/// A portable transcript, deliberately separate from credentials, drafts and workspace state.
struct ChatExport: Codable, Sendable {
    let version: Int
    let title: String
    let messages: [ChatMessage]

    init(title: String, messages: [ChatMessage]) {
        version = 1
        self.title = title
        self.messages = messages.filter(\.hasContent)
    }

    enum Format: String, CaseIterable, Sendable {
        case markdown, pdf, json
        var name: String { self == .markdown ? "Markdown" : rawValue.uppercased() }
        var fileExtension: String { self == .markdown ? "md" : rawValue }
        var contentType: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .pdf: .pdf
            case .json: .json
            }
        }
    }

    var filename: String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let safe = title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return safe.isEmpty ? "Chat" : String(safe.prefix(80))
    }

    var markdown: String {
        var parts = ["# \(title.replacingOccurrences(of: "\n", with: " "))"]
        for message in messages {
            var body = "## \(Self.roleName(message.role))\n\n\(message.text)"
            for attachment in message.attachments ?? [] {
                body += "\n\n### Attachment: \(attachment.name)\n\n"
                if attachment.isImage {
                    body += "Image attachment (binary content included in JSON export)."
                } else {
                    // Pick a fence longer than any backtick run in the attached source.
                    let longest = attachment.text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
                    let fence = String(repeating: "`", count: max(3, longest + 1))
                    body += "\(fence)\n\(attachment.text)\n\(fence)"
                }
            }
            if let state = message.replyState, state != .completed {
                body += "\n\n_Reply status: \(state.rawValue)_"
            }
            if let activities = message.toolActivities, !activities.isEmpty {
                body += "\n\n### Tool activity\n\n" + activities.map { "- \($0.label) (\($0.status))" }.joined(separator: "\n")
            }
            parts.append(body)
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func roleName(_ role: String) -> String {
        role == "user" ? "You" : role.capitalized
    }

    @MainActor func data(for format: Format) throws -> Data {
        switch format {
        case .markdown: return Data(markdown.utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        case .pdf: return try pdfData()
        }
    }

    /// Core Text paginates by visible UTF-16 ranges, including long code and Unicode text.
    @MainActor private func pdfData() throws -> Data {
        let text = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        for block in ChatMarkdown.rendered(markdown).blocks {
            let source: String
            let font: NSFont
            switch block {
            case .prose(let segments), .quote(let segments):
                source = segments.map { String($0.text.characters) }.joined()
                font = .systemFont(ofSize: 11)
            case .heading(let level, let segments):
                source = segments.map { String($0.text.characters) }.joined()
                font = .systemFont(ofSize: level == 1 ? 22 : level == 2 ? 15 : 12, weight: .semibold)
            case .listItem(let marker, let depth, let segments):
                source = String(repeating: "  ", count: depth) + marker + " "
                    + segments.map { String($0.text.characters) }.joined()
                font = .systemFont(ofSize: 11)
            case .divider:
                source = "────────────────────────"
                font = .systemFont(ofSize: 11)
            case .table(let table):
                source = ([table.headers] + table.rows).map { row in
                    row.map { $0.map { String($0.text.characters) }.joined() }.joined(separator: "  |  ")
                }.joined(separator: "\n")
                font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            case .code(let value, _):
                source = value
                font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            }
            text.append(NSAttributedString(string: source + "\n", attributes: [
                .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph,
            ]))
        }
        let result = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: result),
              let context = CGContext(consumer: consumer, mediaBox: &page, [kCGPDFContextTitle: title] as CFDictionary)
        else { throw CocoaError(.fileWriteUnknown) }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
        var offset = 0
        while offset < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            offset += visible.length
        }
        context.closePDF()
        return result as Data
    }
}

extension AppStore {
    func exportTranscript(_ id: UUID) -> ChatExport {
        let saved = conversations.first { $0.id == id }
        let live = chatSessions[id]
        let messages = id == conversationID ? self.messages : live?.messages ?? saved?.messages ?? []
        let title = saved?.title ?? messages.first(where: { $0.role == "user" })?.text ?? "New chat"
        return ChatExport(title: title, messages: messages)
    }
}
