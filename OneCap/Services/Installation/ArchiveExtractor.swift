import Foundation

struct ArchiveExtractor: ArchiveExtracting {
    let runner: any ProcessRunning

    init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }
    func unpack(_ data: Data, source: URL, to directory: URL, rawCommand: String) async throws {
        let path = source.path.lowercased()
        let isArchive = [".zip", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2"].contains { path.hasSuffix($0) }
        if !isArchive {
            try data.write(to: PackageValidation.containedPath(rawCommand, in: directory))
            return
        }
        let archive = directory.deletingLastPathComponent().appendingPathComponent(
            ".download-\(UUID().uuidString)")
        try data.write(to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }
        let listing = try await runner.run("/usr/bin/tar", ["-tf", archive.path])
        for name in listing.split(separator: "\n") where name != "." && name != "./" {
            _ = try PackageValidation.containedPath(String(name), in: directory)
        }
        // macOS bsdtar rejects traversal and extraction through symlinks by default.
        _ = try await runner.run(
            "/usr/bin/tar", ["-xf", archive.path, "-C", directory.path, "--no-same-owner"])
        try Self.validateExtractedLinks(in: directory)
    }
    private static func validateExtractedLinks(in directory: URL) throws {
        if let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        {
            for case let file as URL in files {
                if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path) {
                    let destination =
                    target.hasPrefix("/")
                    ? URL(fileURLWithPath: target)
                    : file.deletingLastPathComponent().appendingPathComponent(target)
                    guard destination.standardizedFileURL.path.hasPrefix(directory.path + "/") else {
                        throw AppFailure("An archive link escapes the installation directory.")
                    }
                }
                guard file.resolvingSymlinksInPath().path.hasPrefix(directory.path + "/") else {
                    throw AppFailure("An archive link escapes the installation directory.")
                }
            }
        }
    }
}
