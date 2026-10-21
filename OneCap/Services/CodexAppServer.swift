import Foundation

/// State for the official app-server protocol. No ACP messages are sent to Codex.
@MainActor final class CodexSessionState {
    var models: [[String: Any]] = []
    var model: String?
    var effort: String?
    var turnID: String?
    var prompting = false
    var stopping = false
    var interruptSent = false
    var loggingIn = false
    var loginID: String?
    var lastMessageID: String?
    var streamedMessages: [String: String] = [:]
    var cancellationTask: Task<Void, Never>?
    private var results: [String: Result<Void, Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]

    func finish(_ key: String, _ result: Result<Void, Error>) {
        deadlines.removeValue(forKey: key)?.cancel()
        if let waiter = waiters.removeValue(forKey: key) { waiter.resume(with: result) }
        else { results[key] = result }
    }

    func wait(_ key: String, timeout: UInt64, onTimeout: @escaping @MainActor () -> Void) async throws {
        if let result = results.removeValue(forKey: key) { return try result.get() }
        try await withCheckedThrowingContinuation { continuation in
            waiters[key] = continuation
            deadlines[key] = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                onTimeout()
            }
        }
    }

    func close(reason: String) {
        cancellationTask?.cancel()
        deadlines.values.forEach { $0.cancel() }
        deadlines.removeAll()
        let pending = Array(waiters.values)
        waiters.removeAll()
        results.removeAll()
        for waiter in pending { waiter.resume(throwing: AppFailure(reason)) }
    }
}

extension ACPConnection {
    func initializeCodex() async throws {
        guard let native = codex else { throw AppFailure("Codex is disconnected.") }
        _ = try await request("initialize", [
            "clientInfo": ["name": "onecap", "title": "OneCap", "version": "0.1.0"],
            "capabilities": ["experimentalApi": false],
        ])
        guard codex === native else { throw CancellationError() }
        try write(["method": "initialized"])
        authMethods = [AuthMethod(json: ["id": "chatgpt", "name": "Sign in with ChatGPT"])].compactMap { $0 }
    }

    func authenticateCodex() async throws {
        guard let native = codex else { throw AppFailure("Codex is disconnected.") }
        native.loggingIn = true
        defer { native.loggingIn = false; native.loginID = nil }
        onStatus?("Signing in to Codex…")
        let result = try await request("account/login/start", ["type": "chatgpt"])
        guard codex === native else { throw CancellationError() }
        guard let id = result["loginId"] as? String,
              let rawURL = result["authUrl"] as? String, let url = LoginURL.validated(rawURL) else {
            throw AppFailure("Codex did not return a valid sign-in page.")
        }
        native.loginID = id
        loginURL = url
        guard onOpenLoginURL?(url) == true else {
            _ = try? await request("account/login/cancel", ["loginId": id])
            throw AppFailure("Could not open the Codex sign-in page.")
        }
        guard codex === native else { throw CancellationError() }
        onStatus?("Complete Codex sign-in in your browser…")
        try await native.wait("login:\(id)", timeout: 300) { [weak self] in
            self?.close(reason: "Codex sign-in timed out. Try signing in again.")
        }
        guard codex === native else { throw CancellationError() }
        let account = try await request("account/read", ["refreshToken": false])
        guard codex === native else { throw CancellationError() }
        guard account["account"] is [String: Any] || account["requiresOpenaiAuth"] as? Bool == false else {
            throw ACPRequestError(code: -32000, message: "Codex authentication required.")
        }
        authenticationRequired = false
        loginURL = nil
    }

    func createCodexSession() async throws {
        guard let native = codex, let workspace else { throw AppFailure("Codex is disconnected.") }
        let account = try await request("account/read", ["refreshToken": false])
        guard codex === native else { throw CancellationError() }
        guard account["account"] is [String: Any] || account["requiresOpenaiAuth"] as? Bool == false else {
            throw ACPRequestError(code: -32000, message: "Codex authentication required.")
        }
        var models: [[String: Any]] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let result = try await request("model/list", params)
            guard codex === native else { throw CancellationError() }
            models += result["data"] as? [[String: Any]] ?? []
            cursor = result["nextCursor"] as? String
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw AppFailure("Codex returned a repeated model catalog cursor.")
            }
        } while cursor != nil
        native.models = models.filter { $0["hidden"] as? Bool != true }
        var params: [String: Any] = [
            "cwd": workspace.path, "sandbox": "workspace-write",
            "approvalPolicy": "on-request", "approvalsReviewer": "user",
        ]
        if let model = native.model { params["model"] = model }
        let result = try await request("thread/start", params)
        guard codex === native else { throw CancellationError() }
        guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String else {
            throw AppFailure("Codex did not create a conversation.")
        }
        sessionID = id
        native.model = result["model"] as? String
        native.effort = result["reasoningEffort"] as? String
        updateCodexOptions()
        sessionReady = true
        authenticationRequired = false
        onStatus?("Ready to chat with Codex.")
    }

    func updateCodexOptions() {
        guard let native = codex else { return }
        var choices = native.models.compactMap { item -> ACPSessionOption.Choice? in
            guard let model = item["model"] as? String else { return nil }
            return .init(id: model, name: item["displayName"] as? String ?? model,
                         detail: item["description"] as? String)
        }
        var options: [ACPSessionOption] = []
        if let model = native.model {
            if !choices.contains(where: { $0.id == model }) { choices.append(.init(id: model, name: model)) }
            options.append(.init(id: "model", name: "Model", category: "model",
                                 currentValue: model, choices: choices, transport: .model))
        }
        let model = native.models.first { $0["model"] as? String == native.model }
        let efforts = (model?["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap {
            item -> ACPSessionOption.Choice? in
            guard let effort = item["reasoningEffort"] as? String else { return nil }
            return .init(id: effort, name: effort.capitalized, detail: item["description"] as? String)
        }
        if !efforts.isEmpty {
            let current = native.effort ?? model?["defaultReasoningEffort"] as? String
            native.effort = efforts.first(where: { $0.id == current })?.id ?? efforts[0].id
            options.append(.init(id: "reasoning_effort", name: "Reasoning", category: "thought_level",
                                 currentValue: native.effort!, choices: efforts))
        }
        sessionOptions = options
    }

    func setCodexOption(_ id: String, value: String) throws {
        guard let native = codex else { throw AppFailure("Codex is disconnected.") }
        switch id {
        case "model":
            native.model = value
            native.effort = nil
        case "reasoning_effort": native.effort = value
        default: throw AppFailure("This Codex setting is unavailable.")
        }
        // App-server applies these overrides on the next turn/start.
        updateCodexOptions()
    }

    func promptCodex(_ input: [[String: String]]) async throws {
        guard let native = codex, let sessionID, !native.prompting else {
            throw AppFailure("Codex is not ready for another message.")
        }
        native.prompting = true
        native.turnID = nil
        native.stopping = false
        native.interruptSent = false
        native.lastMessageID = nil
        native.streamedMessages = [:]
        defer {
            native.prompting = false
            native.cancellationTask?.cancel()
            native.turnID = nil
        }
        var params: [String: Any] = ["threadId": sessionID, "input": input]
        if let model = native.model { params["model"] = model }
        if let effort = native.effort { params["effort"] = effort }
        let response = try await request("turn/start", params)
        guard codex === native else { throw CancellationError() }
        guard let turn = response["turn"] as? [String: Any], let id = turn["id"] as? String else {
            throw AppFailure("Codex did not start a reply.")
        }
        native.turnID = id
        if native.stopping { interruptCodexTurn() }
        try await native.wait("turn:\(id)", timeout: 600) { [weak self] in
            self?.close(reason: "Codex reply timed out. Reconnect to continue.")
        }
    }

    func cancelCodexPrompt() {
        guard let native = codex, native.prompting else {
            close(reason: "Request stopped before Codex started a reply.")
            return
        }
        resolvePermission(nil)
        native.stopping = true
        onStatus?("Stopping reply…")
        interruptCodexTurn()
        native.cancellationTask?.cancel()
        native.cancellationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.close(reason: "Codex did not acknowledge cancellation. Reconnect to continue.")
        }
    }

    private func interruptCodexTurn() {
        guard let native = codex, let sessionID, let turnID = native.turnID,
              !native.interruptSent else { return }
        native.interruptSent = true
        Task { [weak self] in
            guard let self, codex === native, native.prompting else { return }
            do { _ = try await request("turn/interrupt", ["threadId": sessionID, "turnId": turnID]) }
            catch {
                guard codex === native, native.prompting else { return }
                close(reason: "Could not stop the Codex reply. Reconnect to continue.")
            }
        }
    }

    func receiveCodex(_ method: String, params: [String: Any], rpcID: Any?) {
        guard let native = codex else { return }
        if method == "account/login/completed", native.loggingIn, let id = params["loginId"] as? String {
            let result: Result<Void, Error> = params["success"] as? Bool == true ? .success(())
                : .failure(AppFailure(params["error"] as? String ?? "Codex sign-in was not completed."))
            native.finish("login:\(id)", result)
            return
        }
        if let rpcID {
            receiveCodexApproval(method, params: params, rpcID: rpcID)
            return
        }
        guard let sessionID, params["threadId"] as? String == sessionID else { return }
        if method == "thread/name/updated", let name = params["threadName"] as? String {
            onTitle?(name)
            return
        }
        guard native.prompting else { return }
        if let turnID = params["turnId"] as? String, turnID != native.turnID { return }
        if method == "turn/started", let turn = params["turn"] as? [String: Any] {
            if native.turnID == nil { native.turnID = turn["id"] as? String }
            if native.stopping { interruptCodexTurn() }
        } else if method == "item/agentMessage/delta", let id = params["itemId"] as? String,
                  let delta = params["delta"] as? String {
            appendCodexText(delta, itemID: id)
        } else if ["item/started", "item/completed"].contains(method), let item = params["item"] as? [String: Any] {
            if item["type"] as? String == "agentMessage", method == "item/completed" {
                completeCodexMessage(item)
            } else { updateCodexActivity(item, completed: method == "item/completed") }
        } else if method == "turn/completed", let turn = params["turn"] as? [String: Any],
                  let id = turn["id"] as? String, native.turnID == id {
            for item in turn["items"] as? [[String: Any]] ?? [] { completeCodexMessage(item) }
            let result: Result<Void, Error>
            switch turn["status"] as? String {
            case "completed": result = .success(())
            case "interrupted": result = .failure(CancellationError())
            default:
                let error = turn["error"] as? [String: Any]
                let message = error?["message"] as? String ?? "Codex could not complete the reply."
                result = .failure(ACPRequestError(code: -32603, message: message))
            }
            resolvePermission(nil)
            native.finish("turn:\(id)", result)
        } else if method == "serverRequest/resolved", let id = params["requestId"],
                  let permission, String(describing: permission.rpcID) == String(describing: id) {
            self.permission = nil
        }
    }

    private func appendCodexText(_ text: String, itemID: String) {
        guard let native = codex, !text.isEmpty else { return }
        if native.lastMessageID != itemID {
            if native.lastMessageID != nil { onText?("\n\n") }
            native.lastMessageID = itemID
        }
        native.streamedMessages[itemID, default: ""] += text
        onText?(text)
    }

    private func completeCodexMessage(_ item: [String: Any]) {
        guard item["type"] as? String == "agentMessage", let id = item["id"] as? String,
              let text = item["text"] as? String, let native = codex else { return }
        let streamed = native.streamedMessages[id] ?? ""
        if text.hasPrefix(streamed) { appendCodexText(String(text.dropFirst(streamed.count)), itemID: id) }
    }

    private func updateCodexActivity(_ item: [String: Any], completed: Bool) {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return }
        let title: String
        let kind: String
        switch type {
        case "commandExecution": title = item["command"] as? String ?? "Running command"; kind = "execute"
        case "fileChange":
            let files = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            title = files.isEmpty ? "Editing files" : "Editing \(files.joined(separator: ", "))"
            kind = "edit"
        case "webSearch": title = item["query"] as? String ?? "Searching the web"; kind = "search"
        case "imageView": title = item["path"] as? String ?? "Viewing image"; kind = "read"
        case "mcpToolCall", "dynamicToolCall", "collabAgentToolCall":
            title = item["tool"] as? String ?? "Using tool"; kind = "other"
        default: return
        }
        let update: [String: Any] = ["title": title, "kind": kind, "status": completed ? "completed" : "in_progress"]
        if let index = toolActivities.firstIndex(where: { $0.id == id }) { toolActivities[index].merge(update) }
        else {
            var activity = ACPToolActivity(id: id)
            activity.merge(update)
            toolActivities.append(activity)
        }
    }

    private func receiveCodexApproval(_ method: String, params: [String: Any], rpcID: Any) {
        guard params["threadId"] as? String == sessionID, codex?.prompting == true,
              let turnID = codex?.turnID, params["turnId"] as? String == turnID else {
            try? write(["id": rpcID, "error": ["code": -32602, "message": "No matching active Codex turn"]])
            return
        }
        guard ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method) else {
            try? write(["id": rpcID, "error": ["code": -32601, "message": "Client capability is not supported"]])
            return
        }
        guard permission == nil, codex?.stopping != true else {
            try? write(["id": rpcID, "result": ["decision": "cancel"]])
            return
        }
        let advertised = (params["availableDecisions"] as? [Any]).map { values in
            Set(values.compactMap { $0 as? String })
        }
        let options: [PermissionRequest.Option] = [
            .init(id: "accept", name: "Allow once"), .init(id: "decline", name: "Decline"),
        ].filter { advertised == nil || advertised!.contains($0.id) }
        let title = [params["reason"], params["command"], params["cwd"], params["grantRoot"]]
            .compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: "\n")
        permission = .init(rpcID: rpcID, title: title.isEmpty ? "Codex requests permission" : title, options: options)
    }
}
