import Foundation
import Observation

struct PermissionRequest: Identifiable {
    struct Option: Identifiable {
        let id: String
        let name: String
    }
    let id = UUID()
    let rpcID: Any
    let title: String
    let options: [Option]
}

/// ACP v1, newline-delimited JSON-RPC over the agent's stdin/stdout.
@MainActor @Observable final class ACPConnection {
    private var generation = UUID()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var stderr: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var cancellationDeadline: Task<Void, Never>?
    private var sessionID: String?
    private var workspace: URL?
    var sessionOptions: [ACPSessionOption] = []
    private(set) var updatingConfiguration = false
    var authMethods: [AuthMethod] = []
    var permission: PermissionRequest?
    var connected = false
    var sessionReady = false
    var authenticationRequired = false
    var loginURL: URL?
    var onOpenLoginURL: (@MainActor (URL) -> Bool)?
    var onTerminalLogin: (@MainActor (TerminalLoginCommand) async throws -> Void)?
    private var launchAgent: InstalledAgent?
    private var agentName = "Agent"
    private var authenticationRequestID: Int?
    private var openedLoginURLs: Set<URL> = []
    var onText: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    
    func connect(_ agent: InstalledAgent, workspace: URL) async throws {
        close()
        self.workspace = workspace
        launchAgent = agent
        agentName = agent.name
        let token = generation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: agent.executable)
        child.arguments = agent.arguments
        child.currentDirectoryURL = workspace
        child.environment = ProcessInfo.processInfo.environment.merging(agent.environment) { _, new in
            new
        }
        let stdin = Pipe()
        let stdout = Pipe()
        let errors = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = errors
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        stderr = errors.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.receive(data)
            }
        }
        // Drain diagnostics without saving potentially sensitive agent logs.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        child.terminationHandler = { [weak self] child in
            let code = child.terminationStatus
            Task { @MainActor [weak self] in
                guard self?.process === child else { return }
                self?.close(reason: "Agent exited (\(code)).")
            }
        }
        process = child
        do {
            try child.run()
            let result = try await request(
                "initialize",
                [
                    "protocolVersion": 1,
                    "clientCapabilities": [
                        "fs": ["readTextFile": false, "writeTextFile": false], "terminal": false,
                        "elicitation": ["url": [:]],
                        "auth": ["terminal": onTerminalLogin != nil],
                        "_meta": ["terminal-auth": onTerminalLogin != nil],
                    ],
                    "clientInfo": ["name": "OneCap", "version": "0.1.0"],
                ])
            guard token == generation else { throw CancellationError() }
            try Task.checkCancellation()
            guard (result["protocolVersion"] as? Int) == 1 else {
                throw AppFailure("This agent does not support ACP v1.")
            }
            authMethods = (result["authMethods"] as? [[String: Any]] ?? []).compactMap(
                AuthMethod.init(json:))
            connected = true
            onStatus?("Connected. Checking sign-in…")
        } catch {
            if generation == token { close() }
            throw error
        }
    }
    func authenticate(_ method: AuthMethod) async throws {
        sessionID = nil
        sessionReady = false
        sessionOptions = []
        if method.terminal != nil {
            try await authenticateInTerminal(method)
            return
        }
        guard method.isAgentManaged else {
            throw AppFailure("This authentication method is not supported.")
        }
        let token = generation
        openedLoginURLs.removeAll()
        defer { if token == generation { authenticationRequestID = nil } }
        onStatus?("Signing in with \(method.name)…")
        _ = try await request("authenticate", ["methodId": method.id], timeout: 300)
        guard token == generation else { throw CancellationError() }
        try Task.checkCancellation()
        authenticationRequired = false
        loginURL = nil
        onStatus?("Sign-in completed. Preparing chat…")
    }
    
    private func authenticateInTerminal(_ method: AuthMethod) async throws {
        guard let runner = onTerminalLogin, let agent = launchAgent, let directory = workspace else {
            throw AppFailure("Interactive terminal login is unavailable.")
        }
        let command = try TerminalLoginCommand(agent: agent, method: method, directory: directory)
        close(reason: "Sign in to \(agent.name) in the login terminal.")
        let token = generation
        try await runner(command)
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        // Terminal auth changes credentials out of band. Never send authenticate for this method.
        try await connect(agent, workspace: directory)
    }
    
    /// Probe existing credentials before starting any login flow.
    func prepareSession(allowAuthentication: Bool = true) async throws {
        guard connected else { throw AppFailure("Agent is disconnected.") }
        if sessionID != nil { return }
        do {
            try await createSession()
        } catch let error as ACPRequestError where error.authenticationRequired {
            authenticationRequired = true
            guard allowAuthentication else { throw error }
            guard let method = authMethods.first(where: { $0.isSupported }) else {
                throw AppFailure(
                    "This agent requires sign-in but does not offer a supported login method.")
            }
            try await authenticate(method)
            try await createSession()
        }
    }
    
    private func createSession() async throws {
        guard let workspace else { throw AppFailure("Agent is disconnected.") }
        let token = generation
        let result = try await request("session/new", ["cwd": workspace.path, "mcpServers": []])
        guard token == generation else { throw CancellationError() }
        try Task.checkCancellation()
        guard let id = result["sessionId"] as? String else {
            throw AppFailure("The agent did not create a session.")
        }
        sessionID = id
        sessionOptions = ACPSessionOption.decode(result)
        sessionReady = true
        authenticationRequired = false
        onStatus?("Ready to chat.")
    }
    
    func restartSession() async throws {
        let previousOptions = sessionOptions
        sessionID = nil
        sessionReady = false
        try await prepareSession()
        for previous in previousOptions {
            if let current = sessionOptions.first(where: { $0.id == previous.id }),
               current.currentValue != previous.currentValue,
               current.choices.contains(where: { $0.id == previous.currentValue })
            {
                try await setSessionOption(current.id, value: previous.currentValue)
            }
        }
    }
    
    func setSessionOption(_ id: String, value: String) async throws {
        guard let sessionID, sessionReady, !updatingConfiguration,
              let option = sessionOptions.first(where: { $0.id == id }),
              option.choices.contains(where: { $0.id == value })
                else { throw AppFailure("This option is no longer available. Open the model menu again.") }
        guard option.currentValue != value else { return }
        let token = generation
        updatingConfiguration = true
        defer { if generation == token { updatingConfiguration = false } }
        let method: String
        var params: [String: Any] = ["sessionId": sessionID]
        switch option.transport {
        case .config:
            method = "session/set_config_option"
            params["configId"] = id
            params["value"] = value
        case .model:
            method = "session/set_model"
            params["modelId"] = value
        case .mode:
            method = "session/set_mode"
            params["modeId"] = value
        }
        let result = try await request(method, params)
        guard generation == token, self.sessionID == sessionID else { throw CancellationError() }
        if option.transport == .config {
            guard result["configOptions"] is [[String: Any]] else {
                sessionReady = false
                throw AppFailure(
                    "The agent did not confirm its configuration. Reconnect before continuing.")
            }
            sessionOptions = ACPSessionOption.decode(result)
        } else if let index = sessionOptions.firstIndex(where: { $0.id == id }) {
            sessionOptions[index].currentValue = value
        }
    }
    
    func prompt(
        _ text: String, previousMessages: [ChatMessage] = [], attachments: [ChatAttachment] = []
    ) async throws {
        try await prepareSession()
        guard let sessionID else { throw AppFailure("The agent session is not ready.") }
        var blocks: [[String: String]] = []
        if !previousMessages.isEmpty {
            let transcript = previousMessages.map { ["role": $0.role, "content": $0.contentForModel] }
            let data = try JSONSerialization.data(withJSONObject: transcript, options: [.sortedKeys])
            blocks.append([
                "type": "text",
                "text":
                    "Earlier conversation for context only. Do not repeat prior actions; respond to the newest message below.\n"
                + String(decoding: data, as: UTF8.self),
            ])
        }
        if !attachments.isEmpty {
            blocks.append(["type": "text", "text": ChatAttachment.context(attachments)])
        }
        if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
        _ = try await request(
            "session/prompt", ["sessionId": sessionID, "prompt": blocks],
            timeout: 600)
    }
    /// ACP cancellation is a notification: keep the session alive until the prompt acknowledges it.
    func cancelPrompt() {
        guard let sessionID else {
            close(reason: "Request stopped before a session was created.")
            return
        }
        resolvePermission(nil)
        do {
            try write(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sessionID]])
            onStatus?("Stopping reply…")
            cancellationDeadline?.cancel()
            cancellationDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.close(
                    reason:
                        "Reply stopped. The agent did not acknowledge cancellation; reconnect to continue.")
            }
        } catch {
            close(reason: "Could not cancel the request. The agent was disconnected.")
        }
    }
    
    func requireAuthentication() {
        authenticationRequired = true
        sessionReady = false
        sessionID = nil
        sessionOptions = []
        onStatus?("Sign in again to continue.")
    }

    func resolvePermission(_ optionID: String?) {
        guard let permission else { return }
        var outcome: [String: Any] = ["outcome": "cancelled"]
        if let optionID { outcome = ["outcome": "selected", "optionId": optionID] }
        try? write(["jsonrpc": "2.0", "id": permission.rpcID, "result": ["outcome": outcome]])
        self.permission = nil
    }
    func close(reason: String = "Disconnected.") {
        generation = UUID()
        cancellationDeadline?.cancel()
        cancellationDeadline = nil
        resolvePermission(nil)
        output?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
        try? input?.close()
        try? output?.close()
        try? stderr?.close()
        process = nil
        input = nil
        output = nil
        stderr = nil
        buffer.removeAll()
        sessionID = nil
        workspace = nil
        launchAgent = nil
        connected = false
        sessionReady = false
        authenticationRequired = false
        loginURL = nil
        authenticationRequestID = nil
        openedLoginURLs.removeAll()
        authMethods = []
        sessionOptions = []
        updatingConfiguration = false
        let continuations = pending.values
        pending.removeAll()
        deadlines.values.forEach { $0.cancel() }
        deadlines.removeAll()
        for continuation in continuations { continuation.resume(throwing: AppFailure(reason)) }
        onStatus?(reason)
    }
    private func request(_ method: String, _ params: [String: Any], timeout: UInt64 = 60) async throws
    -> [String: Any]
    {
        nextID += 1
        let id = nextID
        if method == "authenticate" { authenticationRequestID = id }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params]) } catch {
                pending.removeValue(forKey: id)?.resume(throwing: error)
                return
            }
            deadlines[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.close(reason: "Agent request timed out. Reconnect to try again.")
            }
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private func write(_ object: [String: Any]) throws {
        guard let input else { throw AppFailure("Agent is disconnected.") }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 16 * 1024 * 1024 else {
            close(reason: "Agent sent an oversized message.")
            return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
                    else { continue }
            if let method = message["method"] as? String {
                let params = message["params"] as? [String: Any] ?? [:]
                if method == "elicitation/create", let rpcID = message["id"] {
                    handleLoginElicitation(params, rpcID: rpcID)
                } else if method == "elicitation/complete" {
                    // The authenticate response confirms success; navigation alone never does.
                } else if method == "session/update", let update = params["update"] as? [String: Any] {
                    // A replaced session may still emit late notifications.
                    guard let sessionID, params["sessionId"] as? String == sessionID else { continue }
                    if update["sessionUpdate"] as? String == "agent_message_chunk",
                       let content = update["content"] as? [String: Any], let text = content["text"] as? String
                    {
                        onText?(text)
                    } else if update["sessionUpdate"] as? String == "config_option_update" {
                        sessionOptions = ACPSessionOption.decode(update)
                    } else if update["sessionUpdate"] as? String == "current_mode_update",
                              let mode = update["currentModeId"] as? String,
                              let index = sessionOptions.firstIndex(where: { $0.transport == .mode })
                    {
                        sessionOptions[index].currentValue = mode
                    } else if let title = update["title"] as? String {
                        onStatus?(title)
                    }
                } else if method == "session/request_permission", let rpcID = message["id"] {
                    guard permission == nil else {
                        try? write([
                            "jsonrpc": "2.0", "id": rpcID, "result": ["outcome": ["outcome": "cancelled"]],
                        ])
                        continue
                    }
                    let tool = params["toolCall"] as? [String: Any]
                    let options = (params["options"] as? [[String: Any]] ?? []).compactMap {
                        item -> PermissionRequest.Option? in
                        guard let id = item["optionId"] as? String else { return nil }
                        return .init(id: id, name: item["name"] as? String ?? id)
                    }
                    permission = .init(
                        rpcID: rpcID, title: tool?["title"] as? String ?? "Agent requests permission",
                        options: options)
                } else if let rpcID = message["id"] {
                    try? write([
                        "jsonrpc": "2.0", "id": rpcID,
                        "error": ["code": -32601, "message": "Client capability is not supported"],
                    ])
                }
            } else if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                deadlines.removeValue(forKey: id)?.cancel()
                if pending.isEmpty, cancellationDeadline != nil {
                    cancellationDeadline?.cancel()
                    cancellationDeadline = nil
                    onStatus?("Reply stopped. Ready for another message.")
                }
                if let error = message["error"] as? [String: Any] {
                    let failure = ACPRequestError(json: error)
                    if failure.authenticationRequired {
                        requireAuthentication()
                    }
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume(
                        returning: (try? JSONSerialization.data(
                            withJSONObject: message["result"] as? [String: Any] ?? [:])) ?? Data("{}".utf8))
                }
            }
        }
    }
    private func handleLoginElicitation(_ params: [String: Any], rpcID: Any) {
        guard params["mode"] as? String == "url",
              let requestID = params["requestId"] as? Int,
              requestID == authenticationRequestID,
              let rawURL = params["url"] as? String,
              let url = LoginURL.validated(rawURL)
                else {
            try? write(["jsonrpc": "2.0", "id": rpcID, "result": ["action": "decline"]])
            return
        }
        loginURL = url
        onStatus?("Sign in to \(agentName) at \(url.host ?? "its website"). Waiting for completion…")
        let opened = openedLoginURLs.contains(url) || onOpenLoginURL?(url) == true
        if opened { openedLoginURLs.insert(url) }
        try? write(["jsonrpc": "2.0", "id": rpcID, "result": ["action": opened ? "accept" : "cancel"]])
        if !opened {
            deadlines.removeValue(forKey: requestID)?.cancel()
            pending.removeValue(forKey: requestID)?.resume(
                throwing: AppFailure("Could not open the login page. Try signing in again."))
        }
    }
    
}
