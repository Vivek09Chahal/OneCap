import Foundation

/// Reuses the attachment reader's UTF-8 and file-size checks. Never executes skill scripts.
actor SkillFiles {
    private let globalDirectory: URL
    private let homeDirectory: URL?
    private let reader = ChatFileImporter()

    init(globalDirectory: URL, homeDirectory: URL? = nil) {
        self.globalDirectory = globalDirectory
        self.homeDirectory = homeDirectory
    }

    func discover(projects: [URL]) async throws -> [SharedSkill] {
        let paths = [".onecap/skills", ".agents/skills", ".claude/skills", ".cursor/skills", ".codex/skills",
            ".opencode/skills", ".github/skills", ".copilot/skills", ".kimi-code/skills"]
        var roots: [(URL, URL?)] = [(globalDirectory, nil)]
        if let homeDirectory {
            roots += (paths + [".config/opencode/skills"]).map { (homeDirectory.appendingPathComponent($0), nil) }
        }
        for project in Set(projects.map(\.standardizedFileURL)).sorted(by: { $0.path < $1.path }) {
            roots += paths.map { (project.appendingPathComponent($0), project) }
        }
        var result: [SharedSkill] = []
        for (root, project) in roots {
            var pending = [(root, 0)]
            var visited: Set<URL> = []
            while let (folder, depth) = pending.popLast() {
                try Task.checkCancellation()
                let canonical = folder.resolvingSymlinksInPath().standardizedFileURL
                guard depth <= 6, visited.count < 2000, visited.insert(canonical).inserted else { continue }
                let file = folder.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: file.path) {
                    do {
                        var skill = try await imported(file, project: project)
                        skill.discovered = true
                        skill.enabled = false
                        result.append(skill)
                    } catch is CancellationError { throw CancellationError() }
                    catch { /* Ignore unreadable or oversized files without blocking other skills. */ }
                    continue
                }
                let children = (try? FileManager.default.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for child in children.sorted(by: { $0.path > $1.path })
                    where ![".git", "node_modules", "scripts", "references", "assets"].contains(child.lastPathComponent) {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        pending.append((child, depth + 1))
                    }
                }
            }
        }
        return result
    }

    func imported(_ url: URL, project: URL?) async throws -> SharedSkill {
        let file = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            ? url.appendingPathComponent("SKILL.md") : url
        guard file.lastPathComponent == "SKILL.md" else { throw AppFailure("Choose a SKILL.md file or its folder.") }
        let text = try await reader.read([file])[0].text
        let lines = text.components(separatedBy: .newlines)
        let header = lines.first == "---" ? Array(lines.dropFirst().prefix { $0 != "---" }) : []
        let name = header.first(where: { $0.hasPrefix("name:") }).map {
            String($0.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return SharedSkill(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? file.deletingLastPathComponent().lastPathComponent,
            file: file.resolvingSymlinksInPath().standardizedFileURL, project: project?.standardizedFileURL)
    }

    /// Install an editable local copy. Re-adding never overwrites the user's changes.
    func install(_ bundled: BundledSkill) async throws -> SharedSkill {
        let folder = globalDirectory.appendingPathComponent("Bundled/\(bundled.id)", isDirectory: true)
        let file = folder.appendingPathComponent("SKILL.md")
        let resources = [("SKILL", "md", "SKILL.md"), ("LICENSE", "txt", "LICENSE"),
                         ("LICENSE-MIT", "txt", "LICENSE-MIT"), ("NOTICE", "txt", "NOTICE"),
                         ("SOURCE", "txt", "SOURCE.txt")]
        let sources = try resources.map { (try bundled.resource($0.0, extension: $0.1), $0.2) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (source, name) in sources {
            let target = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: target.path) {
                try Data(contentsOf: source).write(to: target, options: .withoutOverwriting)
            }
        }
        return try await imported(file, project: nil)
    }

    func read(_ skill: SharedSkill) async throws -> String {
        try await reader.read([skill.file])[0].text
    }

    func create(name: String, text: String, project: URL?) throws -> SharedSkill {
        guard name.count <= 64, name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw AppFailure("Use a skill name such as dsa-context: lowercase letters, numbers, and hyphens, up to 64 characters.")
        }
        let root = project?.appendingPathComponent(".onecap/skills", isDirectory: true) ?? globalDirectory
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let file = folder.appendingPathComponent("SKILL.md")
        try validate(text)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .withoutOverwriting)
        return SharedSkill(name: name, file: file.resolvingSymlinksInPath().standardizedFileURL,
            project: project?.standardizedFileURL)
    }

    func save(_ skill: SharedSkill, text: String) throws {
        try validate(text)
        try Data(text.utf8).write(to: skill.file, options: .atomic)
    }

    func context(_ skills: [SharedSkill], workspace: URL?) async throws -> [ChatAttachment] {
        var result: [ChatAttachment] = []
        var bytes = 0
        var included: Set<URL> = []
        for skill in skills where skill.applies(to: workspace) {
            try Task.checkCancellation()
            if skill.discovered == true && !FileManager.default.fileExists(atPath: skill.file.path) { continue }
            guard included.insert(skill.file.resolvingSymlinksInPath().standardizedFileURL).inserted else { continue }
            let text = try await read(skill)
            bytes += text.utf8.count
            guard bytes <= 1024 * 1024 else { throw AppFailure("Enabled skills exceed 1 MB. Disable some skills on the Skills page.") }
            result.append(ChatAttachment(
                name: "User-enabled skill: \(skill.name) · \(skill.file.path)",
                text: "Skill directory: \(skill.file.deletingLastPathComponent().path)\n\n" + text))
        }
        return result
    }

    private func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains("\0"), text.utf8.count <= ChatFileImporter.maximumBytes else {
            throw AppFailure("Skill content must be nonempty UTF-8 text under 256 KB.")
        }
    }
}
