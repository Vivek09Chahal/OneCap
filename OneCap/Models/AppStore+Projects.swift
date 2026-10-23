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
        rememberProject(folder)
        resetChat()
        workspace = folder.standardizedFileURL
    }

    func removeProject(_ folder: URL) {
        guard !applyingFileUndo, !chatSessions.values.contains(where: {
            $0.sending && $0.workspace?.standardizedFileURL.path == folder.standardizedFileURL.path
        }) else { return }
        let path = folder.standardizedFileURL.path
        if workspace?.standardizedFileURL.path == path {
            // Save the active draft before collecting all of this project's chats.
            resetChat()
            workspace = nil
        }
        let removedIDs = conversations.filter {
            $0.workspace?.standardizedFileURL.path == path
        }.map(\.id)
        for id in removedIDs {
            titleTasks.removeValue(forKey: id)?.cancel()
        }
        conversations.removeAll { $0.workspace?.standardizedFileURL.path == path }
        projectFolders.removeAll { $0.standardizedFileURL.path == path }
        persistHistory()
        persistProjects()
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
