import Foundation

struct ReviewedFileDraft {
    var text: String
    var savedText: String?
    var isDirty: Bool { Data(text.utf8) != Data((savedText ?? "").utf8) }
}

