import Foundation

extension AppStore {
    var agentConnectionKey: AgentConnectionKey? {
        guard chatUsesAgent, let selectedAgentID, !uninstalling.contains(selectedAgentID),
              installed.contains(where: { $0.id == selectedAgentID })
                else { return nil }
        return AgentConnectionKey(
            agentID: selectedAgentID, conversationID: conversationID, folder: workspace)
    }
    
    func selectWorkspace(_ folder: URL?) {
        guard folder != workspace else { return }
        resetChat(preservingDraft: true)
        workspace = folder
        if let folder { rememberProject(folder) }
    }
    
    func changeSessionOption(_ id: String, value: String) async {
        guard !sending, !connecting else { return }
        let token = activeConnectionID
        do {
            try await acp.setSessionOption(id, value: value)
            if activeConnectionID == token { connectionError = nil }
        } catch {
            guard activeConnectionID == token, !(error is CancellationError) else { return }
            connectionError = "Could not change agent option: \(error.localizedDescription)"
        }
    }
    
    /// The app's persistent keyed task calls this on selection, mode, project, and conversation changes.
    func connect() async {
        let session = chatSession
        guard !session.sending, !session.acp.sessionReady, let agent = selectedAgent,
              !uninstalling.contains(agent.id)
                else { return }
        if let reason = AgentCompatibility.unavailableReason(for: agent.id) {
            session.connectionError = reason
            session.status = reason
            return
        }
        let token = UUID()
        session.activeConnectionID = token
        session.connecting = true
        session.connectionError = nil
        session.status = "Connecting to \(agent.name)…"
        defer {
            if session.activeConnectionID == token {
                session.connecting = false
                session.stoppingReply = false
            }
        }
        do {
            try await withTaskCancellationHandler {
                let directory = try await chatDirectories.resolve(
                    selected: session.workspace, conversationID: session.conversationID)
                try Task.checkCancellation()
                guard session.activeConnectionID == token, !session.stoppingReply else { throw CancellationError() }
                try await session.acp.connect(agent, workspace: directory)
                try Task.checkCancellation()
                guard session.activeConnectionID == token else { throw CancellationError() }
                try await session.acp.prepareSession()
                session.agentNeedsHistoryContext = !session.messages.isEmpty
            } onCancel: {
                Task { @MainActor [weak session] in
                    guard let session, session.activeConnectionID == token else { return }
                    session.terminalLogin.cancel()
                    session.acp.close(reason: "Connection cancelled.")
                }
            }
        } catch {
            guard session.activeConnectionID == token, !Task.isCancelled, !session.stoppingReply else { return }
            if error is CancellationError {
                session.status = "Sign-in cancelled. You can retry when ready."
                return
            }
            session.connectionError = ACPAuthenticationFailure.isRequired(error)
                ? "Your agent sign-in has expired or is required. Sign in again to continue; your chat is saved."
                : error.localizedDescription
            session.status = session.connectionError ?? error.localizedDescription
        }
    }
    
    func authenticate(_ method: AuthMethod) async {
        let session = chatSession
        guard !sending, !session.connecting else { return }
        let token = session.activeConnectionID
        session.connecting = true
        session.connectionError = nil
        defer {
            if session.activeConnectionID == token {
                session.connecting = false
                session.stoppingReply = false
            }
        }
        do {
            session.agentNeedsHistoryContext = !session.messages.isEmpty
            try await session.acp.authenticate(method)
            try Task.checkCancellation()
            guard session.activeConnectionID == token, !session.stoppingReply else { return }
            // Verify the replacement credentials once; never open a second login on failure.
            try await session.acp.prepareSession(allowAuthentication: false)
            if session.authenticationNeedsRetry {
                session.connectionError = "Signed in. Retry your last message to continue."
            }
        } catch {
            if session.activeConnectionID == token && !session.stoppingReply {
                if error is CancellationError {
                    session.status = "Sign-in cancelled. You can retry when ready."
                    return
                }
                session.connectionError = ACPAuthenticationFailure.isRequired(error)
                    ? "Sign-in could not be restored. Sign in again using the agent's login method."
                    : error.localizedDescription
                session.status = session.connectionError ?? error.localizedDescription
            }
        }
    }
}
