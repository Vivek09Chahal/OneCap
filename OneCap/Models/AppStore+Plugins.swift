import Foundation

extension AppStore {
    var plugins: [PluginConnection] {
        get { library.plugins }
        set { library.plugins = newValue }
    }

    func loadPlugins() async throws {
        guard !library.pluginsLoaded else { return }
        let saved = try await pluginRepository.load()
        if !library.pluginsLoaded { plugins = saved; library.pluginsLoaded = true }
    }

    func pluginServers(for workspace: URL?) async throws -> [PluginServer] {
        try await loadPlugins()
        return try plugins.filter { $0.applies(to: workspace) }.map {
            PluginServer(connection: $0, token: $0.hasCredential ? try Keychain.read($0.id) : nil)
        }
    }

    func savePlugin(_ connection: PluginConnection, token: String?) async throws {
        try await loadPlugins()
        var updated = connection
        if let token {
            if token.isEmpty { try Keychain.delete(updated.id); updated.hasCredential = false }
            else { try Keychain.save(token, for: updated.id); updated.hasCredential = true }
        }
        var snapshot = plugins
        if let index = snapshot.firstIndex(where: { $0.id == updated.id }) { snapshot[index] = updated }
        else { snapshot.append(updated) }
        try await persistPlugins(snapshot)
    }

    func removePlugin(_ connection: PluginConnection) async throws {
        try await loadPlugins()
        if let identifier = connection.managedConnectionID, let id = UUID(uuidString: identifier),
           let service = connection.managedServiceURL {
            let client = try ManagedPluginClient(baseURL: service, token: Keychain.read(connection.id))
            try await client.disconnect(id)
        }
        try Keychain.delete(connection.id)
        try await persistPlugins(plugins.filter { $0.id != connection.id })
    }

    private func persistPlugins(_ snapshot: [PluginConnection]) async throws {
        let old = plugins
        let revision = UUID()
        plugins = snapshot
        library.pluginRevision = revision
        let previous = library.pluginSaveTask
        let task = Task { [pluginRepository] in
            _ = try? await previous?.value
            try await pluginRepository.save(snapshot)
        }
        library.pluginSaveTask = task
        do { try await task.value }
        catch {
            if library.pluginRevision == revision { plugins = old; library.pluginRevision = UUID() }
            throw error
        }
    }
}
