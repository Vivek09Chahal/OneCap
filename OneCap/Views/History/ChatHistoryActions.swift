import Foundation

/// Feature containers provide behavior; rows and groups only render it.
struct ChatHistoryActions {
    let rename: (UUID, String) -> Void
    let togglePin: (UUID) -> Void
    let toggleArchive: (UUID) -> Void
    let delete: (UUID) -> Void
}
