import Foundation

extension AppStore {
    func attachFiles(_ urls: [URL]) async {
        guard !sending, !connecting, !importingFiles else { return }
        guard draftAttachments.count + urls.count <= ChatFileImporter.maximumFiles else {
            error = "Attach up to five files per message."
            return
        }
        let token = UUID()
        attachmentImportID = token
        let conversation = conversationID
        importingFiles = true
        defer { if attachmentImportID == token { importingFiles = false } }
        do {
            let files = try await fileImporter.read(urls)
            guard conversationID == conversation, attachmentImportID == token else { return }
            draftAttachments.append(contentsOf: files)
            checkpointConversation(touch: false)
        } catch {
            guard conversationID == conversation, attachmentImportID == token else { return }
            self.error = error.localizedDescription
        }
    }
    
    func removeAttachment(_ id: UUID) {
        guard !sending else { return }
        draftAttachments.removeAll { $0.id == id }
        checkpointConversation(touch: false)
    }
}
