import Foundation

/// An @ file token at the caret, independent of the editor used to compose it.
struct ProjectFileQuery: Equatable {
    let text: String
    let range: Range<String.Index>

    static func active(in draft: String, at caret: String.Index? = nil) -> Self? {
        let caret = caret ?? draft.endIndex
        guard caret == draft.endIndex || draft.indices.contains(caret),
              draft[..<caret].last?.isWhitespace == false,
              let token = draft[..<caret].split(whereSeparator: \.isWhitespace).last,
              token.first == "@" else { return nil }
        let end = draft[caret...].firstIndex(where: \.isWhitespace) ?? draft.endIndex
        return Self(text: String(token.dropFirst()), range: token.startIndex..<end)
    }
}
