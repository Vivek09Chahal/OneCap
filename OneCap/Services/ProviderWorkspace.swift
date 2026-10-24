import Foundation

/// Read-only tools for the folder explicitly selected for this conversation.
struct ProviderWorkspace {
    let root: URL
    static let maximumReadBytes = 256 * 1024

    static var tools: [[String: Any]] {
        [tool("list_directory", description: "List up to 500 immediate children of a workspace directory."),
         tool("read_file", description: "Read a UTF-8 text file up to 256 KB inside the workspace.")]
    }

    private static func tool(_ name: String, description: String) -> [String: Any] {
        ["type": "function", "function": [
            "name": name, "description": description,
            "parameters": ["type": "object", "properties": [
                "path": ["type": "string", "description": "Path relative to the selected workspace. Use . for its root."]
            ], "required": ["path"], "additionalProperties": false]
        ]]
    }

    func execute(name: String, arguments: String) throws -> String {
        struct Arguments: Decodable { let path: String }
        guard let data = arguments.data(using: .utf8) else { throw AppFailure("Invalid tool arguments.") }
        let path = try JSONDecoder().decode(Arguments.self, from: data).path
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        let url = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") else {
            throw AppFailure("Access is limited to the selected workspace.")
        }
        switch name {
        case "list_directory":
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw AppFailure("Choose a directory inside the workspace.")
            }
            var listingError: Error?
            guard let entries = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, error in listingError = error; return false }) else {
                throw AppFailure("Could not list this directory.")
            }
            var names: [String] = []
            while let entry = entries.nextObject() as? URL {
                try Task.checkCancellation()
                if names.count == 500 { names.append("[Listing truncated at 500 entries]"); break }
                names.append(entry.lastPathComponent)
            }
            if let listingError { throw listingError }
            return names.sorted().joined(separator: "\n")
        case "read_file":
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw AppFailure("Choose a regular text file inside the workspace.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumReadBytes + 1) ?? Data()
            guard data.count <= Self.maximumReadBytes else { throw AppFailure("File exceeds the 256 KB read limit.") }
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                throw AppFailure("File is not UTF-8 text.")
            }
            return text
        default:
            throw AppFailure("Unknown workspace tool.")
        }
    }
}
