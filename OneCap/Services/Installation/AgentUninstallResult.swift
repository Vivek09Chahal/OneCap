import Foundation

struct AgentUninstallResult: Sendable {
    let state: SavedAppState
    let cleanupError: String?
}
