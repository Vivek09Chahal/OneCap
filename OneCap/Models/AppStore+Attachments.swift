import Foundation

extension AppStore {
    func attachImage(_ data: Data, name: String = "Pasted image.png") async {
        let session = chatSession
        guard !session.importingFiles, session.draftAttachments.count < ChatFileImporter.maximumFiles else {
            error = "Wait for the attachment import or remove a file (maximum five attachments)."
            return
        }
        let token = UUID()
        let conversation = session.conversationID
        session.attachmentImportID = token
        session.importingFiles = true
        defer { if session.attachmentImportID == token { session.importingFiles = false } }
        do {
            let image = try await fileImporter.image(data, name: name)
            guard session.conversationID == conversation, session.attachmentImportID == token else { return }
            session.draftAttachments.append(image)
            checkpointConversation(touch: false, session: session)
        } catch {
            if session.conversationID == conversation, session.attachmentImportID == token { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    func attachFiles(_ urls: [URL], relativeTo folder: URL? = nil) async -> Bool {
        let session = chatSession
        guard !session.importingFiles else { return false }
        guard session.draftAttachments.count + urls.count <= ChatFileImporter.maximumFiles else {
            error = "Attach up to five files per message."
            return false
        }
        let token = UUID()
        session.attachmentImportID = token
        let conversation = session.conversationID
        session.importingFiles = true
        defer { if session.attachmentImportID == token { session.importingFiles = false } }
        do {
            let files = try await fileImporter.read(urls, relativeTo: folder)
            guard session.conversationID == conversation, session.attachmentImportID == token else { return false }
            session.draftAttachments.append(contentsOf: files)
            checkpointConversation(touch: false, session: session)
            return true
        } catch {
            guard session.conversationID == conversation, session.attachmentImportID == token else { return false }
            self.error = error.localizedDescription
            return false
        }
    }
    
    func removeAttachment(_ id: UUID) {
        let session = chatSession
        session.draftAttachments.removeAll { $0.id == id }
        checkpointConversation(touch: false, session: session)
    }
}
