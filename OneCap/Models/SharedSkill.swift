import Foundation

struct SharedSkill: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    let file: URL
    let project: URL?
    var enabled = true
    var discovered: Bool?

    func applies(to workspace: URL?) -> Bool {
        guard enabled else { return false }
        guard let project else { return true }
        guard let workspace else { return false }
        let root = project.resolvingSymlinksInPath().standardizedFileURL.path
        let path = workspace.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
}
