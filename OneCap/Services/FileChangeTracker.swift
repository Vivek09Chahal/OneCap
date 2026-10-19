import Foundation

/// Snapshot regular text files before a turn, independently of Git's working tree.
/// Never follow links or walk dependency/build output directories.
actor FileChangeTracker {
    private static let maximumFileBytes = 512 * 1024
    private static let maximumTotalBytes = 16 * 1024 * 1024
    private static let maximumFiles = 10_000
    private static let omittedDirectories: Set<String> = [
        ".git", "node_modules", ".build", ".swiftpm", ".next", "DerivedData", ".venv", "venv", "__pycache__",
    ]

    func snapshot(_ folder: URL) throws -> FileSnapshot {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
        var snapshot = FileSnapshot(folder: root)
        var pending = [root]
        var bytes = 0
        var count = 0
        while let directory = pending.popLast() {
            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            } catch {
                snapshot.excluded.insert(relative(directory, to: root))
                snapshot.limited = true
                continue
            }
            for url in urls.sorted(by: { $0.path < $1.path }) {
                let path = relative(url, to: root)
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                    guard values.isSymbolicLink != true else { snapshot.excluded.insert(path); continue }
                    if values.isDirectory == true {
                        if !Self.omittedDirectories.contains(url.lastPathComponent) { pending.append(url) }
                        continue
                    }
                    guard values.isRegularFile == true else { snapshot.excluded.insert(path); continue }
                    count += 1
                    let size = values.fileSize ?? 0
                    guard count <= Self.maximumFiles, size <= Self.maximumFileBytes,
                          bytes + size <= Self.maximumTotalBytes else {
                        snapshot.excluded.insert(path)
                        snapshot.limited = true
                        continue
                    }
                    let data = try Data(contentsOf: url)
                    guard !data.contains(0), let text = String(data: data, encoding: .utf8),
                          text.components(separatedBy: "\n").count <= 10_000 else {
                        snapshot.excluded.insert(path)
                        snapshot.limited = true
                        continue
                    }
                    bytes += data.count
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    snapshot.files[path] = .init(text: text, permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue)
                } catch {
                    snapshot.excluded.insert(path)
                    snapshot.limited = true
                }
            }
        }
        return snapshot
    }

    func changes(since before: FileSnapshot, replyID: UUID) throws -> FileChangeSet? {
        let after = try snapshot(before.folder)
        let paths = Set(before.files.keys).union(after.files.keys).sorted()
        let files: [FileEdit] = paths.compactMap { path in
            guard !before.excludes(path), !after.excludes(path) else { return nil }
            let old = before.files[path]
            let new = after.files[path]
            guard old.map({ Data($0.text.utf8) }) != new.map({ Data($0.text.utf8) }) else { return nil }
            let diff = FileTextDiff.make(before: old?.text, after: new?.text)
            return FileEdit(path: path, before: old?.text, after: new?.text,
                            permissions: old?.permissions, additions: diff.added,
                            deletions: diff.removed, diff: diff.text)
        }
        guard !files.isEmpty else { return nil }
        return FileChangeSet(replyID: replyID, folder: before.folder, createdAt: .now, files: files,
            notice: before.limited || after.limited
                ? "Text files up to 512 KB are tracked. Binary, unreadable, oversized files and dependency folders are excluded." : nil)
    }

    /// Validate every file before restoring any; refuse to overwrite subsequent edits.
    func undo(_ changes: FileChangeSet) throws {
        let targets = try changes.files.map { edit -> (FileEdit, URL, Int?) in
            let url = try checkedURL(edit.path, root: changes.folder)
            try checkCurrent(edit, at: url)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (edit, url, (attributes?[.posixPermissions] as? NSNumber)?.intValue)
        }
        var applied: [(FileEdit, URL, Int?)] = []
        do {
            for (edit, url, permissions) in targets {
                _ = try checkedURL(edit.path, root: changes.folder)
                try checkCurrent(edit, at: url)
                applied.append((edit, url, permissions))
                try restore(edit.before, at: url, permissions: edit.permissions)
            }
        } catch {
            var rollbackFailed = false
            for (edit, url, permissions) in applied.reversed() {
                do {
                    _ = try checkedURL(edit.path, root: changes.folder)
                    try restore(edit.after, at: url, permissions: permissions)
                } catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw AppFailure("Undo could not finish restoring every file. Review the files before continuing. \(error.localizedDescription)")
            }
            throw error
        }
    }

    private func checkCurrent(_ edit: FileEdit, at url: URL) throws {
        let current: String?
        if FileManager.default.fileExists(atPath: url.path) {
            current = String(data: try Data(contentsOf: url), encoding: .utf8)
            guard current != nil else { throw AppFailure("Cannot undo: \(edit.path) is no longer a text file.") }
        } else { current = nil }
        guard current.map({ Data($0.utf8) }) == edit.after.map({ Data($0.utf8) }) else {
            throw AppFailure("Cannot undo: \(edit.path) has changed since this reply. Your newer edits were preserved.")
        }
    }

    private func restore(_ text: String?, at url: URL, permissions: Int?) throws {
        if let text {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            if let permissions {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
        } else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func checkedURL(_ path: String, root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AppFailure("The file path cannot be restored.")
        }
        var url = root.standardizedFileURL
        guard url.resolvingSymlinksInPath() == url else { throw AppFailure("The project folder has moved or become a symbolic link.") }
        for part in parts {
            url.appendPathComponent(String(part))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw AppFailure("Cannot undo through a symbolic link: \(path)")
            }
        }
        return url
    }

    private func relative(_ url: URL, to root: URL) -> String {
        // Foundation may return /private/var children for a /var root on macOS.
        String(url.standardizedFileURL.path.dropFirst(root.path.count + (root.path == "/" ? 0 : 1)))
    }
}
