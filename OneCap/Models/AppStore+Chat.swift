import Foundation

extension AppStore {
    func newChat() {
        guard !sending, !applyingFileUndo, !savingReviewedFile else { return }
        resetChat()
        workspace = nil
    }

    func resetChat(preservingDraft: Bool = false) {
        let composedText = preservingDraft ? draft : ""
        let files = preservingDraft ? draftAttachments : []
        attachmentImportID = UUID()
        importingFiles = false
        checkpointConversation(touch: false)
        agentNeedsHistoryContext = false
        conversationID = UUID()
        activeConnectionID = UUID()
        connecting = false
        connectionError = nil
        authenticationNeedsRetry = false
        sendTask?.cancel()
        sendTask = nil
        terminalLogin.cancel()
        acp.close()
        messages = []
        fileChanges = []
        reviewedChanges = nil
        fileChangeError = nil
        cancelEditing()
        draft = composedText
        draftAttachments = files
        queuedMessages = []
        stoppingReply = false
        replyID = nil
        sending = false
    }
    /// Cancels the current reply while preserving the transcript and ACP session.
    func stopReply() {
        guard sending || connecting, !stoppingReply else { return }
        stoppingReply = true
        if let replyID, let index = messages.firstIndex(where: { $0.id == replyID }) {
            messages[index].thinkingTime?.stop()
            messages[index].replyState = .stopped
        }
        terminalLogin.cancel()
        sendTask?.cancel()
        if chatUsesAgent { acp.cancelPrompt() }
        if sendTask == nil {
            acp.close(reason: "Request stopped.")
        }
    }
    
    @discardableResult
    func send(_ text: String, useAgent: Bool) -> Bool {
        guard !stoppingReply, !connecting, !importingFiles, !applyingFileUndo, !savingReviewedFile, !acp.updatingConfiguration,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
                else { return false }
        if useAgent, draftAttachments.contains(where: \.isImage), !acp.supportsImages {
            connectionError = "This agent does not support image attachments. Choose an image-capable agent or remove the image."
            return false
        }
        cancelEditing()
        let message = ChatMessage(role: "user", text: text, attachments: draftAttachments)
        draftAttachments = []
        if sending || !queuedMessages.isEmpty {
            queuedMessages.append(QueuedChatMessage(message: message, usesAgent: useAgent))
            checkpointConversation()
            if !sending { sendNextQueuedMessage() }
            return true
        }
        messages.append(message)
        generateReply(text: text, useAgent: useAgent)
        return true
    }
    
    /// Reused by new messages and edits; ACP edits rebuild context in a fresh session.
    func generateReply(text: String, useAgent: Bool, replacingLastTurn: Bool = false) {
        sending = true
        authenticationNeedsRetry = false
        if useAgent { connectionError = nil }
        stoppingReply = false
        let history = messages
        let includeHistory = replacingLastTurn || agentNeedsHistoryContext
        let reply = ChatMessage(
            role: "assistant", text: "", thinkingTime: ThinkingTime(), replyState: .thinking)
        messages.append(reply)
        replyID = reply.id
        checkpointConversation()
        let generation = conversationID
        let project = workspace
        sendTask = Task {
            var baseline: FileSnapshot?
            var terminalState: ReplyState = .completed
            var titleSource: (provider: Provider, key: String)?
            defer {
                if generation == conversationID {
                    sending = false
                    replyID = nil
                    sendTask = nil
                    stoppingReply = false
                    checkpointConversation()
                    if terminalState == .completed, let titleSource {
                        generateConversationTitle(generation, provider: titleSource.provider, key: titleSource.key)
                    }
                    if terminalState == .completed { sendNextQueuedMessage() }
                }
            }
            do {
                try Task.checkCancellation()
                try await discoverSkills(project: project)
                let sharedContext = try await skillFiles.context(skills, workspace: project)
                try Task.checkCancellation()
                if useAgent {
                    if replacingLastTurn { try await acp.restartSession() }
                    try await acp.prepareSession()
                    try Task.checkCancellation()
                    do {
                        let directory = try await chatDirectories.resolve(selected: project, conversationID: generation)
                        baseline = try await fileChangeTracker.snapshot(directory)
                    } catch {
                        if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                            messages[index].changeTrackingNotice = "File changes could not be tracked: \(error.localizedDescription)"
                        }
                    }
                    try Task.checkCancellation()
                    agentNeedsHistoryContext = false
                    try await acp.prompt(
                        text, previousMessages: includeHistory ? Array(history.dropLast()) : [],
                        attachments: (history.last?.attachments ?? []) + sharedContext)
                } else {
                    guard let provider = selectedProvider else {
                        throw AppFailure("Add and select a provider first.")
                    }
                    let key = try await repository.apiKey(for: provider.id)
                    titleSource = (provider, key)
                    var contextualHistory = history
                    if let index = contextualHistory.lastIndex(where: { $0.role == "user" }), !sharedContext.isEmpty {
                        contextualHistory[index].attachments = (contextualHistory[index].attachments ?? []) + sharedContext
                    }
                    let response = try await providerClient.reply(
                        provider: provider, key: key, messages: contextualHistory)
                    try Task.checkCancellation()
                    if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                        messages[index].thinkingTime?.stop()
                        messages[index].text = response
                    }
                }
                try Task.checkCancellation()
                if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                    messages[index].thinkingTime?.stop()
                    messages[index].replyState = .completed
                    if messages[index].text.isEmpty {
                        messages[index].text = "The agent completed without a text response."
                    }
                }
            } catch {
                terminalState = Task.isCancelled ? .stopped : .failed
                if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                    messages[index].thinkingTime?.stop()
                    messages[index].replyState = Task.isCancelled ? .stopped : .failed
                }
                if !Task.isCancelled && generation == conversationID {
                    let responseText = messages.first(where: { $0.id == reply.id })?.text ?? ""
                    let expiredLogin = ACPAuthenticationFailure.isRequired(error)
                        || (error is ACPRequestError && ACPAuthenticationFailure.isStreamedLoginFailure(responseText))
                    if useAgent && expiredLogin {
                        self.acp.requireAuthentication()
                        self.authenticationNeedsRetry = true
                        self.agentNeedsHistoryContext = true
                        self.connectionError = "Your agent sign-in has expired or is required. Sign in again to continue; your chat is saved."
                        self.status = "Sign in again to continue."
                    } else if useAgent {
                        // Keep request failures in the chat. A global alert must not
                        // take over the split view while its composer is submitting.
                        self.connectionError = "Agent request failed: \(error.localizedDescription)"
                    } else {
                        self.error = error.localizedDescription
                    }
                }
                messages.removeAll { $0.id == reply.id && $0.text.isEmpty }
            }
            // Include edits from failed or stopped replies as well as completed ones.
            if let baseline, generation == conversationID {
                do {
                    if let changes = try await fileChangeTracker.changes(since: baseline, replyID: reply.id),
                       generation == conversationID {
                        fileChanges.append(changes)
                        if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                            messages[index].changeSetID = changes.id
                        } else {
                            messages.append(.init(id: reply.id, role: "assistant", text: "", replyState: terminalState, changeSetID: changes.id))
                        }
                        fileTreeRevision = UUID()
                    }
                } catch {
                    if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                        messages[index].changeTrackingNotice = "File changes could not be read: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
