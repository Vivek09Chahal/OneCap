import DLS
import SwiftUI

struct ChatMessageText: View, Equatable {
    @Environment(\.dlsTheme) private var theme
    let source: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source == rhs.source }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatMarkdown.blocks(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let text):
                    formattedText(text)
                        .textRenderer(ChatCodeRenderer(color: theme.colors.textPrimary.opacity(0.12)))
                case .code(let code):
                    if code.contains("\n") {
                        Text(verbatim: code)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        inlineCode(code)
                            .textRenderer(ChatCodeRenderer(color: theme.colors.textPrimary.opacity(0.12)))
                    }
                }
            }
        }
        .tint(theme.colors.accent)
    }

    private func inlineCode(_ source: String) -> Text {
        Text(verbatim: source)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .customAttribute(ChatCodeAttribute())
    }

    private func formattedText(_ source: String) -> Text {
        ChatMarkdown.segments(source).reduce(Text("")) { result, segment in
            var content = segment.text
            if segment.link != nil { content.foregroundColor = theme.colors.accent }
            let fragment = content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
                ? inlineCode(String(content.characters)) : Text(content)
            if segment.startsLink {
                let globe = Text(Image(systemName: "globe"))
                    .foregroundColor(theme.colors.accent)
                return Text("\(result)\(globe) \(fragment)")
            }
            return Text("\(result)\(fragment)")
        }
    }
}

private struct ChatCodeAttribute: TextAttribute {}

private struct ChatCodeRenderer: TextRenderer {
    let color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var highlight: CGRect?
            func drawHighlight() {
                guard let highlight else { return }
                context.fill(
                    RoundedRectangle(cornerRadius: 4).path(in: highlight.insetBy(dx: -4, dy: 0)),
                    with: .color(color))
            }
            for run in line {
                if run[ChatCodeAttribute.self] != nil {
                    highlight = highlight.map { $0.union(run.typographicBounds.rect) }
                        ?? run.typographicBounds.rect
                } else {
                    drawHighlight()
                    highlight = nil
                }
            }
            drawHighlight()
            for run in line { context.draw(run) }
        }
    }
}
