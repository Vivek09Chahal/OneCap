import Foundation

/// Read just one level on an actor, keeping filesystem work off the UI thread.
actor FolderDirectoryReader {
    func search(_ query: String, in folder: URL) throws -> [FolderEntry] {
        guard !query.isEmpty else { return [] }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let omitted: Set<String> = [".git", "node_modules", ".build", ".swiftpm", ".next", "DerivedData", ".venv", "venv", "__pycache__"]
        var pending = [root]
        var matches: [FolderEntry] = []
        var visited = 0
        while let directory = pending.popLast(), visited < 20_000 {
            try Task.checkCancellation()
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved == root.path || resolved.hasPrefix(root.path + "/") else { continue }
            let entries: [FolderEntry]
            do { entries = try contents(of: directory) }
            catch { if directory == root { throw error }; continue }
            for entry in entries {
                try Task.checkCancellation()
                visited += 1
                guard !entry.isSymbolicLink,
                      entry.url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path + "/") else { continue }
                if entry.isDirectory {
                    if !omitted.contains(entry.name) { pending.append(entry.url) }
                } else if entry.relativePath(in: root).localizedStandardContains(query),
                          (try? entry.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    matches.append(entry)
                }
                if visited >= 20_000 { break }
            }
        }
        return Array(matches.sorted {
            let left = $0.name.localizedStandardContains(query)
            let right = $1.name.localizedStandardContains(query)
            if left != right { return left }
            return $0.relativePath(in: root).localizedStandardCompare($1.relativePath(in: root)) == .orderedAscending
        }.prefix(20))
    }

    func contents(of folder: URL) throws -> [FolderEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        return try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys)
        ).map { url in
            let values = try url.resourceValues(forKeys: keys)
            return FolderEntry(
                url: url, isDirectory: values.isDirectory == true,
                isSymbolicLink: values.isSymbolicLink == true)
        }.sorted {
            if $0.canExpand != $1.canExpand { return $0.canExpand }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
