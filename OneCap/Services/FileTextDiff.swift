import Foundation

/// A line diff retaining line endings so changes to the final newline are visible.
enum FileTextDiff {
    static func make(before: String?, after: String?) -> (text: String, added: Int, removed: Int) {
        let old = lines(before ?? "")
        let new = lines(after ?? "")
        let difference = new.map { Data($0.utf8) }.difference(from: old.map { Data($0.utf8) })
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var output: [String] = []
        var left = 0
        var right = 0
        while left < old.count || right < new.count {
            if left < old.count, removed.contains(left) {
                append(old[left], prefix: "-", to: &output)
                left += 1
            } else if right < new.count, inserted.contains(right) {
                append(new[right], prefix: "+", to: &output)
                right += 1
            } else if left < old.count, right < new.count {
                append(old[left], prefix: " ", to: &output)
                left += 1
                right += 1
            } else { break }
        }
        return (output.joined(separator: "\n"), inserted.count, removed.count)
    }

    private static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices.dropLast() { lines[index] += "\n" }
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func append(_ line: String, prefix: String, to output: inout [String]) {
        output.append(prefix + (line.hasSuffix("\n") ? String(line.dropLast()) : line))
        if !line.hasSuffix("\n") { output.append("\\ No newline at end of file") }
    }
}
