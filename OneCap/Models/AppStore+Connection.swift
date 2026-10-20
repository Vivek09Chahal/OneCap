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
    
    /// SwiftUI's keyed task calls this on selection, mode, project, and conversation changes.
    func connect() async {
        guard !sending, let agent = selectedAgent,
              !uninstalling.contains(agent.id)
                else { return }
        if let reason = AgentCompatibility.unavailableReason(for: agent.id) {
            connectionError = reason
            status = reason
            return
        }
        let token = UUID()
        activeConnectionID = token
        connecting = true
        connectionError = nil
        status = "Connecting to \(agent.name)…"
        defer {
            if activeConnectionID == token {
                connecting = false
                stoppingReply = false
            }
        }
        do {
            try await withTaskCancellationHandler {
                let directory = try await chatDirectories.resolve(
                    selected: workspace, conversationID: conversationID)
                try Task.checkCancellation()
                guard activeConnectionID == token, !stoppingReply else { throw CancellationError() }
                try await acp.connect(agent, workspace: directory)
                try Task.checkCancellation()
                guard activeConnectionID == token else { throw CancellationError() }
                try await acp.prepareSession()
                agentNeedsHistoryContext = !messages.isEmpty
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.activeConnectionID == token else { return }
                    self.terminalLogin.cancel()
                    self.acp.close(reason: "Connection cancelled.")
                }
            }
        } catch {
            guard activeConnectionID == token, !Task.isCancelled, !stoppingReply else { return }
            if error is CancellationError {
                status = "Sign-in cancelled. You can retry when ready."
                return
            }
            connectionError = ACPAuthenticationFailure.isRequired(error)
                ? "Your agent sign-in has expired or is required. Sign in again to continue; your chat is saved."
                : error.localizedDescription
            status = connectionError ?? error.localizedDescription
        }
    }
    
    func authenticate(_ method: AuthMethod) async {
        guard !sending, !connecting else { return }
        let token = activeConnectionID
        connecting = true
        connectionError = nil
        defer {
            if activeConnectionID == token {
                connecting = false
                stoppingReply = false
            }
        }
        do {
            agentNeedsHistoryContext = !messages.isEmpty
            try await acp.authenticate(method)
            try Task.checkCancellation()
            guard activeConnectionID == token, !stoppingReply else { return }
            // Verify the replacement credentials once; never open a second login on failure.
            try await acp.prepareSession(allowAuthentication: false)
            if authenticationNeedsRetry {
                connectionError = "Signed in. Retry your last message to continue."
            }
        } catch {
            if activeConnectionID == token && !stoppingReply {
                if error is CancellationError {
                    status = "Sign-in cancelled. You can retry when ready."
                    return
                }
                connectionError = ACPAuthenticationFailure.isRequired(error)
                    ? "Sign-in could not be restored. Sign in again using the agent's login method."
                    : error.localizedDescription
                status = connectionError ?? error.localizedDescription
            }
        }
    }
}
