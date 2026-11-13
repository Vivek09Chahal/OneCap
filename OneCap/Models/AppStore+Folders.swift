import Foundation

extension AppStore {
    func loadFolders() async {
        do {
            let saved = try await folderRepository.load()
            if chatFolders != saved { chatFolders = saved }
            foldersLoaded = true
            persistFolders()
        } catch {
            self.error = "Could not load folders: \(error.localizedDescription)"
        }
    }

    /// Creates a new in-app folder. Returns the new folder.
    @discardableResult
    func createFolder(named name: String) -> ChatFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !chatFolders.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let folder = ChatFolder(name: trimmed)
        chatFolders.append(folder)
        persistFolders()
        return folder
    }

    func renameFolder(_ folder: ChatFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = chatFolders.firstIndex(where: { $0.id == folder.id }),
              chatFolders[index].name != trimmed else { return }
        chatFolders[index].name = trimmed
        persistFolders()
    }

    func deleteFolder(_ folder: ChatFolder) {
        // Remove the folder from all conversations that reference it.
        let folderID = folder.id
        for index in conversations.indices where conversations[index].folderID == folderID {
            conversations[index].folderID = nil
        }
        chatFolders.removeAll { $0.id == folder.id }
        persistHistory()
        persistFolders()
    }

    private func persistFolders() {
        guard foldersLoaded else { return }
        let folders = chatFolders
        let previous = folderSaveTask
        folderSaveTask = Task {
            await previous?.value
            do { try await folderRepository.save(folders) } catch {
                self.error = "Could not save folders: \(error.localizedDescription)"
            }
        }
    }

    /// Starts a new chat inside the given folder. The chat is not tied to a project.
    func newChat(inFolder folder: ChatFolder) {
        guard !applyingFileUndo, !savingReviewedFile else { return }
        resetChat()
        workspace = nil
        folderID = folder.id
    }

    /// Moves an existing conversation into (or out of) a folder. Passing nil removes
    /// the conversation from its folder, making it a simple chat again.
    func moveConversation(_ id: UUID, toFolder folder: ChatFolder?) {
        guard !sending,
              let index = conversations.firstIndex(where: { $0.id == id })
        else { return }
        // A conversation belongs either to a project or a folder, not both.
        conversations[index].folderID = folder?.id
        if folder != nil { conversations[index].workspace = nil }
        persistHistory()
    }
}
