import Foundation

extension AppStore {
    func loadSkills() async throws {
        guard !skillsLoaded else { return }
        let saved = try await skillRepository.load()
        if !skillsLoaded { skills = saved; skillsLoaded = true }
    }

    func saveSkill(_ skill: SharedSkill) async throws {
        try await loadSkills()
        if let index = skills.firstIndex(where: {
            $0.id == skill.id || ($0.file.resolvingSymlinksInPath().standardizedFileURL == skill.file.resolvingSymlinksInPath().standardizedFileURL && $0.project == skill.project)
        }) {
            var updated = skill
            updated.id = skills[index].id
            skills[index] = updated
        } else {
            skills.append(skill)
        }
        try await persistSkills()
    }

    func discoverSkills(project: URL? = nil) async throws {
        try await loadSkills()
        let found = try await skillFiles.discover(projects: projectFolders + [project, workspace].compactMap { $0 })
        var changed = false
        for skill in found where !skills.contains(where: { $0.file == skill.file && $0.project == skill.project }) {
            skills.append(skill)
            changed = true
        }
        // Keep saved toggles even when a discovered file is temporarily unavailable.
        if changed { try await persistSkills() }
    }

    func removeSkill(_ skill: SharedSkill) async throws {
        try await loadSkills()
        skills.removeAll { $0.id == skill.id }
        try await persistSkills()
    }

    private func persistSkills() async throws {
        let previous = skillSaveTask
        let snapshot = skills
        let task = Task { [skillRepository] in
            _ = try? await previous?.value
            try await skillRepository.save(snapshot)
        }
        skillSaveTask = task
        try await task.value
    }
}
