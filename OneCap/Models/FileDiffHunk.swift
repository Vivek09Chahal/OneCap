import Foundation

enum HunkDecision: String, Codable, Sendable {
    case accepted, rejected
}

/// Stable ranges refer to the original snapshots, even after another hunk is rejected.
struct FileDiffHunk: Identifiable, Sendable {
    let id: Int
    let oldRange: Range<Int>
    let newRange: Range<Int>
    let oldLines: [String]
    let newLines: [String]
    var leadingContext: [String] = []
    var trailingContext: [String] = []
}

extension FileEdit {
    var hunks: [FileDiffHunk] {
        let old = FileTextDiff.lines(before ?? "")
        let new = FileTextDiff.lines(after ?? "")
        let difference = new.map { Data($0.utf8) }.difference(from: old.map { Data($0.utf8) })
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [FileDiffHunk] = []
        var left = 0
        var right = 0
        while left < old.count || right < new.count {
            let startLeft = left
            let startRight = right
            while left < old.count && removed.contains(left) { left += 1 }
            while right < new.count && inserted.contains(right) { right += 1 }
            if left != startLeft || right != startRight {
                result.append(FileDiffHunk(id: result.count, oldRange: startLeft..<left, newRange: startRight..<right,
                    oldLines: Array(old[startLeft..<left]), newLines: Array(new[startRight..<right])))
            } else {
                left += 1
                right += 1
            }
        }
        // Creating or deleting an empty file still needs a reviewable change.
        if result.isEmpty, (before == nil) != (after == nil) {
            result.append(FileDiffHunk(id: 0, oldRange: 0..<0, newRange: 0..<0, oldLines: [], newLines: []))
        }
        return result.enumerated().map { index, original in
            var hunk = original
            let previousEnd = index == 0 ? 0 : result[index - 1].oldRange.upperBound
            let nextStart = index + 1 == result.count ? old.count : result[index + 1].oldRange.lowerBound
            hunk.leadingContext = Array(old[max(previousEnd, hunk.oldRange.lowerBound - 3)..<hunk.oldRange.lowerBound])
            hunk.trailingContext = Array(old[hunk.oldRange.upperBound..<min(nextStart, hunk.oldRange.upperBound + 3)])
            return hunk
        }
    }

    var reviewedAfter: String? {
        let hunks = hunks
        let rejected = hunks.filter { hunkDecisions?[$0.id] == .rejected }
        guard !rejected.isEmpty else { return after }
        if rejected.count == hunks.count { return before }
        var lines = FileTextDiff.lines(after ?? "")
        for hunk in rejected.reversed() {
            lines.replaceSubrange(hunk.newRange, with: hunk.oldLines)
        }
        return lines.joined()
    }

    /// Used by the full-file editor and diff after partial rejection.
    var reviewedEdit: FileEdit {
        guard hunkDecisions?.values.contains(.rejected) == true else { return self }
        let result = FileTextDiff.make(before: before, after: reviewedAfter)
        return FileEdit(path: path, before: before, after: reviewedAfter, permissions: permissions,
            additions: result.added, deletions: result.removed, diff: result.text)
    }
}
