import Foundation

/// Shares one in-flight runtime installation across concurrent agent installs.
actor NodeRuntime: NodeRuntimeProviding {
    private let root: URL
    private let downloader: any Downloading
    private let archive: any ArchiveExtracting
    private var installation: Task<URL, Error>?
    
    init(root: URL, downloader: any Downloading = HTTPDownloader(),
         archive: any ArchiveExtracting = ArchiveExtractor()) {
        self.root = root
        self.downloader = downloader
        self.archive = archive
    }
    
    func binary() async throws -> URL {
        if let installation { return try await installation.value }
        let task = Task { try await installRuntime() }
        installation = task
        defer { installation = nil }
        return try await task.value
    }
    private func installRuntime() async throws -> URL {
        let runtimeRoot = root.appendingPathComponent("runtimes")
        let marker = runtimeRoot.appendingPathComponent("node-path.txt")
        if let path = try? String(contentsOf: marker, encoding: .utf8),
           FileManager.default.isExecutableFile(atPath: path)
        {
            return URL(fileURLWithPath: path)
        }
        let releases = try JSONDecoder().decode(
            [NodeRelease].self,
            from: await downloader.data(URL(string: "https://nodejs.org/dist/index.json")!))
        guard
            let release = releases.first(where: {
                if case .active = $0.lts { return true }
                return false
            })
                else { throw AppFailure("No Node.js LTS runtime is available.") }
        let version = try PackageValidation.safeComponent(release.version)
#if arch(arm64)
        let arch = "arm64"
#else
        let arch = "x64"
#endif
        let name = "node-\(version)-darwin-\(arch)"
        let archiveName = name + ".tar.gz"
        let base = URL(string: "https://nodejs.org/dist/\(version)/")!
        async let checksumDownload = downloader.data(base.appendingPathComponent("SHASUMS256.txt"))
        async let archiveDownload = downloader.data(base.appendingPathComponent(archiveName))
        let checksums = try await checksumDownload
        guard
            let line = String(decoding: checksums, as: UTF8.self).split(separator: "\n").first(where: {
                $0.split(whereSeparator: \.isWhitespace).last == Substring(archiveName)
            }),
            let hash = line.split(whereSeparator: \.isWhitespace).first
                else { throw AppFailure("Node.js checksum was not found.") }
        let data = try await archiveDownload
        try PackageValidation.verify(data, sha256: String(hash))
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        let stage = runtimeRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try await archive.unpack(
            data, source: base.appendingPathComponent(archiveName), to: stage, rawCommand: "node")
        let destination = runtimeRoot.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: stage.appendingPathComponent(name), to: destination)
        }
        let node = destination.appendingPathComponent("bin/node")
        guard FileManager.default.isExecutableFile(atPath: node.path) else {
            throw AppFailure("Node.js installation is incomplete.")
        }
        try node.path.write(to: marker, atomically: true, encoding: .utf8)
        return node
    }
}
