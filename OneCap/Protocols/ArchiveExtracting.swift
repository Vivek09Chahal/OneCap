import Foundation

protocol ArchiveExtracting: Sendable {
    func unpack(_ data: Data, source: URL, to directory: URL, rawCommand: String) async throws
}
