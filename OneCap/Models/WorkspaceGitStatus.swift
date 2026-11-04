import Foundation

struct WorkspaceGitStatus: Sendable {
    enum Change: String, Sendable {
        case modified = "M", added = "A", deleted = "D", renamed = "R", conflicted = "U"

        var label: String {
            switch self {
            case .modified: "Modified"
            case .added: "Added"
            case .deleted: "Deleted"
            case .renamed: "Renamed"
            case .conflicted: "Conflicted"
            }
        }
    }

    let branch: String
    let ahead: Int
    let behind: Int
    let changes: [URL: Change]
    let directories: Set<URL>
    var modified: Int { changes.count }

    static func read(in folder: URL) async -> Self? {
        let runner = ProcessRunner()
        guard let rootPath = try? await runner.run("/usr/bin/git", ["-C", folder.path, "rev-parse", "--show-toplevel"]),
              let output = try? await runner.run(
                "/usr/bin/git", ["-C", folder.path, "status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"]
              ) else { return nil }
        // Git's porcelain paths are relative to the repository root, even for a nested workspace.
        let root = URL(fileURLWithPath: rootPath.trimmingCharacters(in: .newlines), isDirectory: true)
            .resolvingSymlinksInPath()
        let workspace = folder.resolvingSymlinksInPath().path
        var branch = "Detached HEAD"
        var ahead = 0
        var behind = 0
        var changes: [URL: Change] = [:]
        var directories: Set<URL> = []
        var skipRenameSource = false
        for record in output.split(separator: "\0") {
            if skipRenameSource { skipRenameSource = false; continue }
            if record.hasPrefix("# branch.head ") {
                let name = String(record.dropFirst(14))
                if name != "(detached)" { branch = name }
            } else if record.hasPrefix("# branch.ab ") {
                let counts = record.dropFirst(12).split(separator: " ")
                ahead = counts.first.flatMap { Int($0.dropFirst()) } ?? 0
                behind = counts.last.flatMap { Int($0.dropFirst()) } ?? 0
            } else {
                let fields: [Substring]
                let change: Change
                if record.hasPrefix("? ") {
                    fields = record.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                    change = .added
                } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") || record.hasPrefix("u ") {
                    skipRenameSource = record.hasPrefix("2 ")
                    let splits = record.hasPrefix("u ") ? 10 : skipRenameSource ? 9 : 8
                    fields = record.split(separator: " ", maxSplits: splits, omittingEmptySubsequences: false)
                    guard fields.count == splits + 1 else { continue }
                    let status = fields[1]
                    if record.hasPrefix("u ") { change = .conflicted }
                    else if status.contains("D") { change = .deleted }
                    else if status.contains("R") { change = .renamed }
                    else if status.contains("A") { change = .added }
                    else { change = .modified }
                } else { continue }
                guard let path = fields.last else { continue }
                let repositoryURL = root.appendingPathComponent(String(path))
                guard repositoryURL.path.hasPrefix(workspace + "/") else { continue }
                // Keep the workspace's URL spelling for row lookups. Standardization can
                // resolve existing files differently from deleted files on macOS.
                let relativePath = String(repositoryURL.path.dropFirst(workspace.count + 1))
                let url = folder.appendingPathComponent(relativePath)
                changes[url] = change
                var parent = url.deletingLastPathComponent()
                while parent.path.hasPrefix(folder.path + "/") {
                    directories.insert(parent)
                    parent.deleteLastPathComponent()
                }
            }
        }
        return Self(branch: branch, ahead: ahead, behind: behind, changes: changes, directories: directories)
    }
}
