import Foundation

actor ChatFileImporter {
    static let maximumFiles = 5
    static let maximumBytes = 256 * 1024
    
    func read(_ urls: [URL]) throws -> [ChatAttachment] {
        guard urls.count <= Self.maximumFiles else {
            throw AppFailure("Attach up to five files per message.")
        }
        return try urls.map { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw AppFailure("Choose a regular text or code file.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes else {
                throw AppFailure("\(url.lastPathComponent) exceeds the 256 KB attachment limit.")
            }
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                throw AppFailure(
                    "\(url.lastPathComponent) is not a UTF-8 text file. Attach a text or code file instead.")
            }
            return ChatAttachment(name: url.lastPathComponent, text: text)
        }
    }
}
