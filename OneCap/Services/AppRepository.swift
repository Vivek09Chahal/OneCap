import Foundation

struct SavedAppState: Codable, Sendable {
    var installed: [InstalledAgent] = []
    var providers: [Provider] = []
    var selectedAgentID: String?
}

/// Serializes read-modify-write transactions so concurrent installs cannot lose settings.
/// Filesystem and Keychain work stays off the main actor.
actor AppRepository {
    private let url: URL
    private var state: SavedAppState?
    
    init(url: URL) { self.url = url }
    
    func load() throws -> SavedAppState {
        if let state { return state }
        let loaded =
        FileManager.default.fileExists(atPath: url.path)
        ? try JSONDecoder().decode(SavedAppState.self, from: Data(contentsOf: url))
        : SavedAppState()
        var migrated = loaded
        if !migrated.installed.contains(where: {
            $0.id == migrated.selectedAgentID && AgentCompatibility.unavailableReason(for: $0.id) == nil
        }) {
            migrated.selectedAgentID =
            migrated.installed.first(where: { AgentCompatibility.unavailableReason(for: $0.id) == nil }
            )?.id
        }
        state = migrated
        return migrated
    }
    
    func register(_ agent: InstalledAgent) throws -> SavedAppState {
        var next = try load()
        if let index = next.installed.firstIndex(where: { $0.id == agent.id }) {
            next.installed[index] = agent
        } else {
            next.installed.append(agent)
        }
        if !next.installed.contains(where: {
            $0.id == next.selectedAgentID && AgentCompatibility.unavailableReason(for: $0.id) == nil
        }) {
            next.selectedAgentID =
            next.installed.first(where: { AgentCompatibility.unavailableReason(for: $0.id) == nil })?.id
        }
        try persist(next)
        return next
    }
    
    func unregisterAgent(_ id: String) throws -> SavedAppState {
        var next = try load()
        next.installed.removeAll { $0.id == id }
        if next.selectedAgentID == id {
            next.selectedAgentID =
            next.installed.first(where: { AgentCompatibility.unavailableReason(for: $0.id) == nil })?.id
        }
        try persist(next)
        return next
    }
    
    func selectAgent(_ id: String?) throws {
        var next = try load()
        if let id, let reason = AgentCompatibility.unavailableReason(for: id) {
            throw AppFailure(reason)
        }
        guard id == nil || next.installed.contains(where: { $0.id == id }) else {
            throw AppFailure("This agent is not installed.")
        }
        next.selectedAgentID = id
        try persist(next)
    }
    
    func addProvider(_ provider: Provider, key: String) throws -> [Provider] {
        var next = try load()
        try Keychain.save(key, for: provider.id)
        next.providers.append(provider)
        do { try persist(next) } catch {
            try? Keychain.delete(provider.id)
            throw error
        }
        return next.providers
    }
    
    func removeProvider(_ provider: Provider) throws -> [Provider] {
        let previous = try load()
        var next = previous
        next.providers.removeAll { $0.id == provider.id }
        try persist(next)
        do { try Keychain.delete(provider.id) } catch {
            try? persist(previous)
            throw error
        }
        return next.providers
    }
    
    func apiKey(for id: UUID) throws -> String { try Keychain.read(id) }
    
    private func persist(_ next: SavedAppState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        state = next
    }
}
