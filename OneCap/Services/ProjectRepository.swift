import Foundation

/// Project membership persists independently of the conversation snapshots.
typealias ProjectRepository = JSONFileRepository<[URL]>
