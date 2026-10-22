import Foundation
import HighlightSwift

/// Highlight complete snapshots so multiline syntax remains correct across diff rows.
actor FileSyntaxHighlighter {
    static let shared = FileSyntaxHighlighter()
    private let highlight = Highlight()
    private struct CodeKey: Hashable {
        let source: String
        let language: String
        let dark: Bool
    }
    private var codeCache: [CodeKey: AttributedString] = [:]
    private var codeOrder: [CodeKey] = []

    func code(_ source: String, language: String?, dark: Bool) async throws -> AttributedString {
        guard source.utf8.count <= 64 * 1024 else { return AttributedString(source) }
        let key = CodeKey(source: source, language: language?.lowercased() ?? "plaintext", dark: dark)
        if let cached = codeCache[key] { return cached }
        let lines = try await sourceLines(source, language: key.language, dark: dark)
        var text = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { text.append(AttributedString("\n")) }
            text.append(line)
        }
        if codeCache[key] == nil { codeOrder.append(key) }
        codeCache[key] = text
        while codeOrder.count > 64 { codeCache.removeValue(forKey: codeOrder.removeFirst()) }
        return text
    }

    func lines(for file: FileEdit, dark: Bool) async throws -> [AttributedString] {
        let name = URL(fileURLWithPath: file.path).lastPathComponent.lowercased()
        let language: String
        switch URL(fileURLWithPath: file.path).pathExtension.lowercased() {
        case "jsx": language = "javascript"
        case "tsx": language = "typescript"
        case "h", "hpp", "cc", "cxx": language = "cpp"
        case "m", "mm": language = "objectivec"
        case "zsh": language = "bash"
        case "": language = name == "dockerfile" || name == "makefile" ? name : "plaintext"
        default: language = URL(fileURLWithPath: file.path).pathExtension.lowercased()
        }
        let old = try await sourceLines(file.before ?? "", language: language, dark: dark)
        let new = try await sourceLines(file.after ?? "", language: language, dark: dark)
        var left = 0
        var right = 0
        return file.diff.components(separatedBy: "\n").map { line in
            let source: AttributedString?
            switch line.first {
            case "-":
                source = old.indices.contains(left) ? old[left] : nil
                left += 1
            case "+":
                source = new.indices.contains(right) ? new[right] : nil
                right += 1
            case " ":
                source = new.indices.contains(right) ? new[right] : nil
                left += 1
                right += 1
            default: return AttributedString(line)
            }
            guard let source, String(source.characters) == String(line.dropFirst()) else { return AttributedString(line) }
            return AttributedString(String(line.prefix(1))) + source
        }
    }

    private func sourceLines(_ text: String, language: String, dark: Bool) async throws -> [AttributedString] {
        try Task.checkCancellation()
        var colored = AttributedString(text)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let result = try? await highlight.request(text, mode: .languageAliasIgnoreIllegal(language),
                colors: dark ? .dark(.github) : .light(.github)) {
            // The HTML importer may trim outer whitespace. Restore it without changing source text.
            let rendered = String(result.attributedText.characters)
            if !rendered.isEmpty, let range = text.range(of: rendered) {
                colored = AttributedString(String(text[..<range.lowerBound])) + result.attributedText
                    + AttributedString(String(text[range.upperBound...]))
            }
        }
        try Task.checkCancellation()
        var lines: [AttributedString] = []
        var start = colored.startIndex
        while let newline = colored[start...].range(of: "\n") {
            lines.append(AttributedString(colored[start..<newline.lowerBound]))
            start = newline.upperBound
        }
        lines.append(AttributedString(colored[start...]))
        return lines
    }
}
