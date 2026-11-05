import Foundation

extension AppStore {
    var pluginPackages: [InstalledPluginPackage] { library.pluginPackages }
    var pluginPackageIssues: [String] { library.pluginPackageIssues }

    func refreshPluginPackages() async {
        do {
            let discovered = try await packageRegistry.discover()
            library.pluginPackages = discovered.packages
            library.pluginPackageIssues = discovered.issues
        } catch {
            library.pluginPackages = []
            library.pluginPackageIssues = [error.localizedDescription]
        }
    }

    func installPluginPackage(from folder: URL) async throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        try await packageRegistry.install(from: folder)
        await refreshPluginPackages()
    }

    func enablePluginPackage(_ package: InstalledPluginPackage, enabled: Bool) async throws {
        try await packageRegistry.setEnabled(package, enabled)
        await refreshPluginPackages()
    }

    func removePluginPackage(_ package: InstalledPluginPackage) async throws {
        try await packageRegistry.remove(package)
        await refreshPluginPackages()
    }

    func executePluginCommand(_ package: InstalledPluginPackage, command: PluginManifest.Feature, arguments: PluginJSON) async throws -> String {
        guard !runningPluginCommand else { throw AppFailure("A plugin command is already running.") }
        runningPluginCommand = true
        defer { runningPluginCommand = false }
        let workspace = workspace
        return try await PluginPackageRuntime(registry: packageRegistry).execute(
            package, kind: "commands/execute", name: command.id, arguments: arguments, workspace: workspace)
    }
}
