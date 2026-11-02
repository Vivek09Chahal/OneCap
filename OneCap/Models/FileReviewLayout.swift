import Foundation

/// Prepared outside SwiftUI layout; decisions do not change the original diff ranges.
struct FileReviewLayout: Sendable {
    struct Row: Identifiable, Sendable {
        let id: Int
        let hunkID: Int
        let isHeading: Bool
        let oldLine: Int?
        let newLine: Int?
        let marker: String
        let text: String
        let missingNewline: Bool
    }

    let hunks: [FileDiffHunk]
    let rows: [Row]

    init(file: FileEdit) {
        hunks = file.hunks
        var result: [Row] = []
        for hunk in hunks {
            result.append(Row(id: result.count, hunkID: hunk.id, isHeading: true,
                oldLine: nil, newLine: nil, marker: "", text: "@@ −\(hunk.oldRange.lowerBound + 1),\(hunk.oldRange.count) +\(hunk.newRange.lowerBound + 1),\(hunk.newRange.count) @@", missingNewline: false))
            func append(_ lines: [String], oldStart: Int?, newStart: Int?, marker: String) {
                for (index, line) in lines.enumerated() {
                    result.append(Row(id: result.count, hunkID: hunk.id, isHeading: false,
                        oldLine: oldStart.map { $0 + index + 1 }, newLine: newStart.map { $0 + index + 1 },
                        marker: marker, text: line.hasSuffix("\n") ? String(line.dropLast()) : line,
                        missingNewline: !line.hasSuffix("\n")))
                }
            }
            append(hunk.leadingContext, oldStart: hunk.oldRange.lowerBound - hunk.leadingContext.count,
                newStart: hunk.newRange.lowerBound - hunk.leadingContext.count, marker: " ")
            append(hunk.oldLines, oldStart: hunk.oldRange.lowerBound, newStart: nil, marker: "−")
            append(hunk.newLines, oldStart: nil, newStart: hunk.newRange.lowerBound, marker: "+")
            append(hunk.trailingContext, oldStart: hunk.oldRange.upperBound, newStart: hunk.newRange.upperBound, marker: " ")
            if hunk.oldLines.isEmpty && hunk.newLines.isEmpty {
                result.append(Row(id: result.count, hunkID: hunk.id, isHeading: false,
                    oldLine: nil, newLine: nil, marker: " ",
                    text: file.before == nil ? "Empty file added" : "Empty file deleted", missingNewline: false))
            }
        }
        rows = result
    }
}

actor FileReviewLayoutCache {
    static let shared = FileReviewLayoutCache()
    struct Key: Hashable, Sendable {
        let before: Data?
        let after: Data?
        init(file: FileEdit) { before = file.before.map { Data($0.utf8) }; after = file.after.map { Data($0.utf8) } }
    }
    private var cached: [Key: FileReviewLayout] = [:]
    private var order: [Key] = []

    func layout(for file: FileEdit) throws -> FileReviewLayout {
        try Task.checkCancellation()
        let key = Key(file: file)
        if let layout = cached[key] { return layout }
        let layout = FileReviewLayout(file: file)
        try Task.checkCancellation()
        cached[key] = layout
        order.append(key)
        while order.count > 8 { cached.removeValue(forKey: order.removeFirst()) }
        return layout
    }
}
