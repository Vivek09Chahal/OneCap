import Foundation

extension AppStore {
    @discardableResult
    func attachFiles(_ urls: [URL], relativeTo folder: URL? = nil) async -> Bool {
        guard !sending, !connecting, !importingFiles else { return false }
        guard draftAttachments.count + urls.count <= ChatFileImporter.maximumFiles else {
            error = "Attach up to five files per message."
            return false
        }
        let token = UUID()
        attachmentImportID = token
        let conversation = conversationID
        importingFiles = true
        defer { if attachmentImportID == token { importingFiles = false } }
        do {
            let files = try await fileImporter.read(urls, relativeTo: folder)
            guard conversationID == conversation, attachmentImportID == token else { return false }
            draftAttachments.append(contentsOf: files)
            checkpointConversation(touch: false)
            return true
        } catch {
            guard conversationID == conversation, attachmentImportID == token else { return false }
            self.error = error.localizedDescription
            return false
        }
    }
    
    func removeAttachment(_ id: UUID) {
        guard !sending else { return }
        draftAttachments.removeAll { $0.id == id }
        checkpointConversation(touch: false)
    }
}
