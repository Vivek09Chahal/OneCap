import Foundation

extension AppStore {
    func loadProjects() async {
        do {
            let saved = try await projectRepository.load()
            for folder in saved + conversations.compactMap(\.workspace) {
                rememberProject(folder)
            }
            projectsLoaded = true
            persistProjects()
        } catch {
            self.error = "Could not load projects: \(error.localizedDescription)"
        }
    }
    
    func rememberProject(_ folder: URL) {
        let folder = folder.standardizedFileURL
        guard !projectFolders.contains(where: { $0.path == folder.path }) else { return }
        projectFolders.append(folder)
        persistProjects()
    }
    
    func openProject(_ folder: URL) {
        guard !sending else { return }
        rememberProject(folder)
        if workspace?.standardizedFileURL.path == folder.standardizedFileURL.path { return }
        if let latest = conversations.filter({
            !$0.isArchived && $0.workspace?.standardizedFileURL.path == folder.standardizedFileURL.path
        })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            openConversation(latest.id)
        } else {
            newProjectChat(in: folder)
        }
    }
    
    func newProjectChat(in folder: URL) {
        guard !sending else { return }
        rememberProject(folder)
        resetChat()
        workspace = folder.standardizedFileURL
    }
    
    private func persistProjects() {
        guard projectsLoaded else { return }
        let folders = projectFolders
        let previous = projectSaveTask
        projectSaveTask = Task {
            await previous?.value
            do { try await projectRepository.save(folders) } catch {
                self.error = "Could not save projects: \(error.localizedDescription)"
            }
        }
    }
}
