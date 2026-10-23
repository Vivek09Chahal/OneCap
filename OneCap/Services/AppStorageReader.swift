import Foundation

struct AppStorageUsage: Sendable {
    enum Category: String, CaseIterable, Sendable {
        case application = "Application"
        case chats = "Chats"
        case workspaces = "Workspaces"
        case agents = "Agents & runtimes"
        case skills = "Skills"
        case other = "Other"
    }

    var bytes: [Category: Int64] = [:]
    var locations: [Category: [URL]] = [:]
    var unreadableItems = 0
    var total: Int64 { bytes.values.reduce(0, +) }
}

/// Measures only OneCap-owned files, without following links into user projects.
/// Runs away from the main actor so large agent installations do not block the UI.
actor AppStorageReader {
    let root: URL
    private let application: URL?
    private let caches: URL?
    private let preferences: URL?

    init(root: URL, application: URL? = Bundle.main.bundleURL,
         caches: URL? = nil, preferences: URL? = nil) {
        self.root = root
        self.application = application?.pathExtension == "app" ? application : nil
        let identifier = Bundle.main.bundleIdentifier
        self.caches = caches ?? identifier.map {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent($0)
        }
        self.preferences = preferences ?? identifier.map {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\($0).plist")
        }
    }

    func measure() throws -> AppStorageUsage {
        var usage = AppStorageUsage()
        usage.locations = [
            .application: application.map { [$0] } ?? [],
            .chats: [root.appendingPathComponent("conversations.json")],
            .workspaces: [root.appendingPathComponent("ChatWorkspaces")],
            .agents: [root.appendingPathComponent("agents"), root.appendingPathComponent("runtimes")],
            .skills: [root.appendingPathComponent("Skills"), root.appendingPathComponent("skills.json")],
            .other: [caches, preferences].compactMap { $0 }
        ]
        try scan(root, category: .other, classifyChildren: true, usage: &usage)
        if let application { try scan(application, category: .application, usage: &usage) }
        if let caches { try scan(caches, category: .other, usage: &usage) }
        if let preferences { try scan(preferences, category: .other, usage: &usage) }
        return usage
    }

    private func scan(_ url: URL, category: AppStorageUsage.Category,
                      classifyChildren: Bool = false, usage: inout AppStorageUsage) throws {
        var pending: [(URL, AppStorageUsage.Category, Bool)] = [(url, category, classifyChildren)]
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
                                       .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        while let (item, category, classify) = pending.popLast() {
            try Task.checkCancellation()
            do {
                let values = try item.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    let children = try FileManager.default.contentsOfDirectory(at: item,
                        includingPropertiesForKeys: Array(keys))
                    for child in children {
                        let group = classify ? Self.category(for: child.lastPathComponent) : category
                        if classify && group == .other {
                            usage.locations[.other, default: []].append(child)
                        }
                        pending.append((child, group, false))
                    }
                } else if values.isRegularFile == true {
                    let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
                    usage.bytes[category, default: 0] += Int64(size)
                }
            } catch {
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain ||
                    ![NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                    usage.unreadableItems += 1
                }
            }
        }
    }

    private static func category(for name: String) -> AppStorageUsage.Category {
        switch name {
        case "conversations.json": .chats
        case "ChatWorkspaces": .workspaces
        case "agents", "runtimes": .agents
        case "Skills", "skills.json": .skills
        default: .other
        }
    }
}
