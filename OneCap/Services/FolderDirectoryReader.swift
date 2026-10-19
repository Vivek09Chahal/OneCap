import Foundation

/// Read just one level on an actor, keeping filesystem work off the UI thread.
actor FolderDirectoryReader {
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
