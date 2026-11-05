import Foundation
import CryptoKit

/// Discovery reads manifests only. Unapproved packages never execute during scanning.
actor PluginPackageRegistry {
    let directory: URL
    private let manager = FileManager.default
    private struct Approval: Codable { let digest: String; let enabled: Bool }
    private var approvalsURL: URL { directory.appendingPathComponent("approvals.json") }

    init(directory: URL) { self.directory = directory }

    func discover() throws -> (packages: [InstalledPluginPackage], issues: [String]) {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let approvals = try loadApprovals()
        var packages: [InstalledPluginPackage] = []
        var issues: [String] = []
        for folder in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted(by: { $0.path < $1.path }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw AppFailure("Plugin folders cannot be symbolic links.")
                }
                let (manifest, digest) = try inspect(folder)
                guard !packages.contains(where: { $0.id == manifest.id }) else { throw AppFailure("Duplicate plugin ID: \(manifest.id)") }
                let approval = approvals[manifest.id]
                packages.append(.init(manifest: manifest, directory: folder,
                                      enabled: approval?.digest == digest && approval?.enabled == true))
            } catch { issues.append("\(folder.lastPathComponent): \(error.localizedDescription)") }
        }
        return (packages.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }, issues)
    }

    func install(from source: URL) throws {
        let (manifest, _) = try inspect(source)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(manifest.id)
        guard !manager.fileExists(atPath: destination.path),
              !(try discover().packages.contains { $0.id == manifest.id }) else {
            throw AppFailure("This plugin is already installed. Remove it before installing a replacement.")
        }
        // Stage, validate, and move atomically; installation does not run any plugin code.
        let staging = directory.appendingPathComponent(".install-" + UUID().uuidString)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        _ = try inspect(staging)
        try manager.moveItem(at: staging, to: destination)
    }

    func setEnabled(_ package: InstalledPluginPackage, _ enabled: Bool) throws {
        try requireInstalled(package)
        let (manifest, digest) = try inspect(package.directory)
        guard manifest == package.manifest else { throw AppFailure("The plugin changed. Refresh and review it again.") }
        var approvals = try loadApprovals()
        approvals[package.id] = Approval(digest: digest, enabled: enabled)
        try JSONEncoder().encode(approvals).write(to: approvalsURL, options: .atomic)
    }

    func remove(_ package: InstalledPluginPackage) throws {
        try requireInstalled(package)
        try manager.removeItem(at: package.directory)
        var approvals = try loadApprovals()
        approvals.removeValue(forKey: package.id)
        try JSONEncoder().encode(approvals).write(to: approvalsURL, options: .atomic)
    }

    func approved(_ package: InstalledPluginPackage) throws -> InstalledPluginPackage {
        try requireInstalled(package)
        let (manifest, digest) = try inspect(package.directory)
        let approval = try loadApprovals()[package.id]
        guard package.enabled, manifest == package.manifest, approval?.enabled == true, approval?.digest == digest else {
            throw AppFailure("This plugin is disabled or its files changed. Review and enable it in Plugins.")
        }
        return package
    }

    private func requireInstalled(_ package: InstalledPluginPackage) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let folder = package.directory.resolvingSymlinksInPath().standardizedFileURL
        guard folder.deletingLastPathComponent() == root else { throw AppFailure("Plugin is outside the installation directory.") }
    }

    private func loadApprovals() throws -> [String: Approval] {
        guard manager.fileExists(atPath: approvalsURL.path) else { return [:] }
        return try JSONDecoder().decode([String: Approval].self, from: Data(contentsOf: approvalsURL))
    }

    private func inspect(_ directory: URL) throws -> (PluginManifest, String) {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        // Reject symlinks and oversized packages. Hash every file so edits require renewed trust.
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else {
            throw AppFailure("Cannot read plugin package.")
        }
        var entries: [(String, Data)] = []
        var total = 0
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw AppFailure("Plugin packages cannot contain symbolic links.") }
            guard values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
            guard total <= 10 * 1024 * 1024, entries.count < 500 else { throw AppFailure("Plugin package exceeds 10 MB or 500 files.") }
            entries.append((String(file.path.dropFirst(root.path.count)), try Data(contentsOf: file)))
        }
        let manifestURL = directory.appendingPathComponent("plugin.json")
        let data = try Data(contentsOf: manifestURL)
        guard data.count <= 128 * 1024 else { throw AppFailure("Plugin manifest exceeds 128 KB.") }
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        _ = try manifest.validate(in: directory)
        var hash = SHA256()
        for (path, content) in entries.sorted(by: { $0.0 < $1.0 }) {
            hash.update(data: Data("\(path.utf8.count):\(path):\(content.count):".utf8))
            hash.update(data: content)
        }
        return (manifest, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
