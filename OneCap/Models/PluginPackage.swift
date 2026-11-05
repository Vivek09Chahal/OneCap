import Foundation

/// Versioned extension points. Features come from packages, never from per-plugin host code.
struct PluginManifest: Codable, Sendable, Equatable {
    struct Feature: Codable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let description: String
        let inputSchema: PluginJSON
    }
    let apiVersion: Int
    let id: String
    let name: String
    let version: String
    let summary: String
    let entrypoint: String
    let interpreter: String?
    let commands: [Feature]
    let tools: [Feature]

    func validate(in directory: URL) throws -> URL {
        let identifier = #/^[a-z0-9][a-z0-9.-]{0,99}$/#
        guard apiVersion == 1, id.wholeMatch(of: identifier) != nil,
              !name.isEmpty, name.count <= 100, !version.isEmpty, summary.count <= 2000,
              commands.count + tools.count > 0, commands.count + tools.count <= 64,
              Set(commands.map(\.id)).count == commands.count,
              Set(tools.map(\.id)).count == tools.count else {
            throw AppFailure("Invalid plugin manifest or unsupported plugin API version.")
        }
        for feature in commands + tools {
            guard feature.id.wholeMatch(of: identifier) != nil, !feature.title.isEmpty,
                  feature.description.count <= 4000, feature.inputSchema["type"]?.string == "object" else {
                throw AppFailure("Plugin features need unique identifiers and object input schemas.")
            }
        }
        if let interpreter, !["/usr/bin/python3", "/bin/sh", "/usr/bin/osascript"].contains(interpreter) {
            throw AppFailure("Unsupported plugin interpreter. Use Python, shell, AppleScript, or a package executable.")
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let file = directory.appendingPathComponent(entrypoint).resolvingSymlinksInPath().standardizedFileURL
        guard !entrypoint.hasPrefix("/"), file.path.hasPrefix(root.path + "/"),
              try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw AppFailure("The plugin entrypoint must be a regular file inside its package.")
        }
        return file
    }
}

struct InstalledPluginPackage: Identifiable, Sendable, Equatable {
    let manifest: PluginManifest
    let directory: URL
    var enabled: Bool
    var id: String { manifest.id }
}

struct PluginCommandSelection: Identifiable {
    let id = UUID()
    let package: InstalledPluginPackage
    let command: PluginManifest.Feature
}
