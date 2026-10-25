import DLS
import SwiftUI

struct ChatMessageText: View, Equatable {
    @Environment(\.dlsTheme) private var theme
    let source: String
    var isAssistant = true
    @State private var rendered: ChatMarkdown.RenderedMessage?
    @State private var renderedSource: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source == rhs.source && lhs.isAssistant == rhs.isAssistant }

    var body: some View {
        let blocks = rendered?.blocks ?? []
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .padding(.top, blockSpacing(at: index, in: blocks))
            }
        }
        .font(.system(size: 14, weight: isAssistant ? .light : .regular))
        .lineSpacing(isAssistant ? 8 : 4)
        .tint(theme.colors.accent)
        .task(id: source) {
            guard renderedSource != source else { return }
            // A keyed task cancels obsolete streaming renders before publishing.
            let result = await ChatMarkdown.renderInBackground(source)
            guard !Task.isCancelled else { return }
            rendered = result
            renderedSource = source
        }
    }

    private func blockSpacing(at index: Int, in blocks: [ChatMarkdown.RenderedBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        guard isAssistant else { return 8 }
        if blocks[index].isListItem && blocks[index - 1].isListItem { return 10 }
        if case .heading = blocks[index] { return 28 }
        if case .heading = blocks[index - 1] { return 16 }
        return 24
    }

    @ViewBuilder private func blockView(_ block: ChatMarkdown.RenderedBlock) -> some View {
        switch block {
        case .prose(let segments): styledText(segments)
        case .heading(let level, let segments):
            styledText(segments, codeSize: headingSize(level))
                .font(.system(size: headingSize(level), weight: isAssistant ? .medium : .semibold))
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let depth, let segments):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).frame(minWidth: 14, alignment: .trailing)
                styledText(segments)
            }
            .padding(.leading, CGFloat(min(depth, 12)) * 16 + 4)
        case .quote(let segments):
            HStack(spacing: 12) {
                Rectangle().fill(theme.colors.borderStrong).frame(width: 3)
                styledText(segments).foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.vertical, isAssistant ? 6 : 0)
            .fixedSize(horizontal: false, vertical: true)
        case .table(let table): tableView(table)
        case .divider: Divider().overlay(theme.colors.border)
        case .code(let code, let language): ChatCodeBlock(source: code, language: language)
        }
    }

    private func tableView(_ table: ChatMarkdown.Table) -> some View {
        ViewThatFits(in: .horizontal) {
            tableGrid(table, columnWidth: 240)
            tableGrid(table, columnWidth: 180)
            tableGrid(table, columnWidth: 140)
            ScrollView(.horizontal) {
                tableGrid(table, columnWidth: 180)
                    .padding(.bottom, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table, \(table.headers.count) columns, \(table.rows.count) rows")
    }

    private func tableGrid(_ table: ChatMarkdown.Table, columnWidth: CGFloat) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            tableRow(table.headers, alignments: table.alignments, columnWidth: columnWidth, isHeader: true)
            ForEach(table.rows.indices, id: \.self) { row in
                Divider().overlay(theme.colors.border).gridCellUnsizedAxes(.horizontal)
                tableRow(table.rows[row], alignments: table.alignments, columnWidth: columnWidth,
                         isHeader: false, alternate: row.isMultiple(of: 2))
            }
        }
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func tableRow(_ cells: [[ChatMarkdown.Segment]], alignments: [ChatMarkdown.ColumnAlignment],
                          columnWidth: CGFloat, isHeader: Bool, alternate: Bool = false) -> some View {
        GridRow(alignment: .top) {
            ForEach(cells.indices, id: \.self) { column in
                let alignment: Alignment = switch alignments[column] {
                case .leading: .leading
                case .center: .center
                case .trailing: .trailing
                }
                styledText(cells[column])
                    .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
                    .lineSpacing(4)
                    .multilineTextAlignment(alignments[column] == .center ? .center
                        : alignments[column] == .trailing ? .trailing : .leading)
                    .frame(width: columnWidth - 24, alignment: alignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(theme.colors.textPrimary.opacity(isHeader ? 0.06 : alternate ? 0.02 : 0))
                    .overlay(alignment: .trailing) {
                        if column < cells.count - 1 {
                            Rectangle().fill(theme.colors.border).frame(width: 1)
                        }
                    }
                    .accessibilityAddTraits(isHeader ? .isHeader : [])
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        isAssistant ? (level == 1 ? 21 : level == 2 ? 19 : level == 3 ? 16 : 14) : 14
    }

    private func styledText(_ segments: [ChatMarkdown.Segment], codeSize: CGFloat? = nil) -> some View {
        formattedText(segments, codeSize: codeSize)
            .textRenderer(ChatCodeRenderer(color: theme.colors.textPrimary.opacity(0.10)))
    }

    private func inlineCode(_ source: String, size: CGFloat? = nil) -> Text {
        Text(verbatim: source)
            .font(.system(size: size ?? 13, weight: isAssistant ? .light : .regular, design: .monospaced))
            .customAttribute(ChatCodeAttribute())
    }

    private func formattedText(_ segments: [ChatMarkdown.Segment], codeSize: CGFloat? = nil) -> Text {
        segments.reduce(Text("")) { result, segment in
            var content = segment.text
            if segment.link != nil { content.foregroundColor = theme.colors.accent }
            let fragment = content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
                ? inlineCode(String(content.characters), size: codeSize) : Text(content)
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
                    RoundedRectangle(cornerRadius: 4).path(in: highlight.insetBy(dx: -2, dy: 0)),
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
