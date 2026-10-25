import Foundation

extension AppStore {
    func closeChatSessions() {
        for session in Array(chatSessions.values) + [chatSession] {
            checkpointConversation(touch: false, session: session)
            session.sendTask?.cancel()
            session.terminalLogin.cancel()
            session.acp.close()
        }
    }

    func newChat() {
        guard !applyingFileUndo, !savingReviewedFile else { return }
        resetChat()
        workspace = nil
    }

    func resetChat(preservingDraft: Bool = false) {
        let composedText = preservingDraft ? draft : ""
        let files = preservingDraft ? draftAttachments : []
        attachmentImportID = UUID()
        importingFiles = false
        checkpointConversation(touch: false)
        if sending {
            chatSessions[conversationID] = chatSession
        } else {
            terminalLogin.cancel()
            acp.close()
            chatSessions.removeValue(forKey: conversationID)
        }
        let session = ChatSession(openLoginURL: openLoginURL)
        session.chatUsesAgent = chatUsesAgent
        session.selectedAgentID = selectedAgentID
        session.selectedProviderID = selectedProviderID
        session.draft = composedText
        session.draftAttachments = files
        configureSession(session)
        chatSession = session
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
        if !useAgent && selectedProvider == nil {
            connectionError = "Choose a saved provider model to continue this chat. The previous provider may have been removed."
            return false
        }
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
    func generateReply(text: String, useAgent: Bool, replacingLastTurn: Bool = false, in targetSession: ChatSession? = nil) {
        let session = targetSession ?? chatSession
        chatSessions[session.conversationID] = session
        session.sending = true
        session.authenticationNeedsRetry = false
        session.connectionError = nil
        session.stoppingReply = false
        let history = session.messages
        let includeHistory = replacingLastTurn || session.agentNeedsHistoryContext
        let reply = ChatMessage(
            role: "assistant", text: "", thinkingTime: ThinkingTime(), replyState: .thinking)
        session.messages.append(reply)
        session.replyID = reply.id
        checkpointConversation(session: session)
        let generation = session.conversationID
        let project = session.workspace
        session.sendTask = Task {
            var baseline: FileSnapshot?
            var terminalState: ReplyState = .completed
            var titleSource: (provider: Provider, key: String)?
            defer {
                if chatSessions[generation] === session {
                    session.sending = false
                    session.replyID = nil
                    session.sendTask = nil
                    session.stoppingReply = false
                    checkpointConversation(session: session)
                    if terminalState == .completed, let titleSource {
                        generateConversationTitle(generation, provider: titleSource.provider, key: titleSource.key)
                    }
                    if terminalState == .completed { sendNextQueuedMessage(in: session) }
                }
            }
            do {
                try Task.checkCancellation()
                try await discoverSkills(project: project)
                let sharedContext = try await skillFiles.context(skills, workspace: project)
                try Task.checkCancellation()
                if useAgent {
                    if replacingLastTurn { try await session.acp.restartSession() }
                    try await session.acp.prepareSession()
                    try Task.checkCancellation()
                    do {
                        let directory = try await chatDirectories.resolve(selected: project, conversationID: generation)
                        baseline = try await session.fileChangeTracker.snapshot(directory)
                    } catch {
                        if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                            session.messages[index].changeTrackingNotice = "File changes could not be tracked: \(error.localizedDescription)"
                        }
                    }
                    try Task.checkCancellation()
                    session.agentNeedsHistoryContext = false
                    try await session.acp.prompt(
                        text, previousMessages: includeHistory ? Array(history.dropLast()) : [],
                        attachments: (history.last?.attachments ?? []) + sharedContext)
                } else {
                    guard let provider = providers.first(where: { $0.id == session.selectedProviderID }) else {
                        throw AppFailure("Add and select a provider first.")
                    }
                    let key = try await repository.apiKey(for: provider.id)
                    titleSource = (provider, key)
                    var contextualHistory = history
                    if let index = contextualHistory.lastIndex(where: { $0.role == "user" }), !sharedContext.isEmpty {
                        contextualHistory[index].attachments = (contextualHistory[index].attachments ?? []) + sharedContext
                    }
                    let response = try await providerClient.reply(
                        provider: provider, key: key, messages: contextualHistory, workspace: project)
                    try Task.checkCancellation()
                    if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                        session.messages[index].thinkingTime?.stop()
                        session.messages[index].text = response
                    }
                }
                try Task.checkCancellation()
                if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                    session.messages[index].thinkingTime?.stop()
                    session.messages[index].replyState = .completed
                    if session.messages[index].text.isEmpty {
                        session.messages[index].text = "The agent completed without a text response."
                    }
                }
            } catch {
                terminalState = Task.isCancelled ? .stopped : .failed
                if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                    session.messages[index].thinkingTime?.stop()
                    session.messages[index].replyState = Task.isCancelled ? .stopped : .failed
                }
                if !Task.isCancelled && generation == session.conversationID {
                    let responseText = session.messages.first(where: { $0.id == reply.id })?.text ?? ""
                    let expiredLogin = ACPAuthenticationFailure.isRequired(error)
                        || (error is ACPRequestError && ACPAuthenticationFailure.isStreamedLoginFailure(responseText))
                    if useAgent && expiredLogin {
                        session.acp.requireAuthentication()
                        session.authenticationNeedsRetry = true
                        session.agentNeedsHistoryContext = true
                        session.connectionError = "Your agent sign-in has expired or is required. Sign in again to continue; your chat is saved."
                        session.status = "Sign in again to continue."
                    } else if useAgent {
                        // Keep request failures in the chat. A global alert must not
                        // take over the split view while its composer is submitting.
                        session.connectionError = "Agent request failed: \(error.localizedDescription)"
                    } else {
                        session.connectionError = "Provider request failed: \(error.localizedDescription)"
                    }
                }
                session.messages.removeAll { $0.id == reply.id && $0.text.isEmpty }
            }
            // Include edits from failed or stopped replies as well as completed ones.
            if let baseline, generation == session.conversationID {
                do {
                    if let changes = try await session.fileChangeTracker.changes(since: baseline, replyID: reply.id),
                       generation == session.conversationID {
                        session.fileChanges.append(changes)
                        if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                            session.messages[index].changeSetID = changes.id
                        } else {
                            session.messages.append(.init(id: reply.id, role: "assistant", text: "", replyState: terminalState, changeSetID: changes.id))
                        }
                        session.fileTreeRevision = UUID()
                    }
                } catch {
                    if let index = session.messages.firstIndex(where: { $0.id == reply.id }) {
                        session.messages[index].changeTrackingNotice = "File changes could not be read: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
