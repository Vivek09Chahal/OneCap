import Foundation

struct FolderEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var canExpand: Bool { isDirectory && !isSymbolicLink }
    var symbol: String { isSymbolicLink ? "link" : isDirectory ? "folder" : "doc" }

    func relativePath(in folder: URL) -> String {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return String(url.standardizedFileURL.path.dropFirst(root.count + 1))
    }
}
