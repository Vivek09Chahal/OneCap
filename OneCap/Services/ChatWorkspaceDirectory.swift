import Foundation

/// ACP always needs a cwd; a private per-conversation directory makes project selection optional.
actor ChatWorkspaceDirectory {
    private let root: URL
    
    init(root: URL) { self.root = root }
    
    func resolve(selected: URL?, conversationID: UUID) throws -> URL {
        if let selected { return selected }
        let directory = root.appendingPathComponent(conversationID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }
}
