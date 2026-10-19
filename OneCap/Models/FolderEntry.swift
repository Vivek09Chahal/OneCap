import Foundation

struct FolderEntry: Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var canExpand: Bool { isDirectory && !isSymbolicLink }
    var symbol: String { isSymbolicLink ? "link" : isDirectory ? "folder" : "doc" }
}
