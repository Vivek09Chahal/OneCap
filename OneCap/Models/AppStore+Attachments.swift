import Foundation

extension AppStore {
    func attachImage(_ data: Data, name: String = "Pasted image.png") async {
        guard !importingFiles, draftAttachments.count < ChatFileImporter.maximumFiles else {
            error = "Wait for the attachment import or remove a file (maximum five attachments)."
            return
        }
        let token = UUID()
        let conversation = conversationID
        attachmentImportID = token
        importingFiles = true
        defer { if attachmentImportID == token { importingFiles = false } }
        do {
            let image = try await fileImporter.image(data, name: name)
            guard conversationID == conversation, attachmentImportID == token else { return }
            draftAttachments.append(image)
            checkpointConversation(touch: false)
        } catch {
            if conversationID == conversation, attachmentImportID == token { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    func attachFiles(_ urls: [URL], relativeTo folder: URL? = nil) async -> Bool {
        guard !importingFiles else { return false }
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
        draftAttachments.removeAll { $0.id == id }
        checkpointConversation(touch: false)
    }
}
