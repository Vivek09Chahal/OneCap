import Foundation

struct FileChangeSet: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    let replyID: UUID
    let folder: URL
    let createdAt: Date
    var files: [FileEdit]
    var revertedAt: Date?
    var notice: String?

    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

struct FileEdit: Identifiable, Codable, Sendable, Equatable {
    let path: String
    let before: String?
    let after: String?
    let permissions: Int?
    let additions: Int
    let deletions: Int
    let diff: String
    var id: String { path }
    var status: String { before == nil ? "Added" : after == nil ? "Deleted" : "Modified" }
}

struct FileSnapshot: Sendable {
    struct Content: Sendable {
        let text: String
        let permissions: Int?
    }
    let folder: URL
    var files: [String: Content] = [:]
    var excluded: Set<String> = []
    var limited = false

    func excludes(_ path: String) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
