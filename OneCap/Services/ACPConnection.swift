import Foundation
import Observation

/// Tool updates are partial: retain the title and kind when only status changes.
struct ACPToolActivity: Identifiable, Equatable {
    let id: String
    var title: String?
    var kind: String?
    var status = "pending"
    var filePaths: [String] = []

    mutating func merge(_ update: [String: Any]) {
        if let title = update["title"] as? String { self.title = title }
        if let kind = update["kind"] as? String { self.kind = kind }
        if let status = update["status"] as? String { self.status = status }
        if let locations = update["locations"] as? [[String: Any]] {
            var seen = Set<String>()
            filePaths = locations.compactMap { $0["path"] as? String }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }
    }

    var isActive: Bool { status == "pending" || status == "in_progress" }
    var label: String {
        if kind == "edit" || kind == "delete" || kind == "move" {
            if !filePaths.isEmpty { return "Editing \(filePaths.joined(separator: ", "))" }
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title.lowercased().hasPrefix("editing ") ? title : "Editing files: \(title)"
            }
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return phase
    }

    var phase: String {
        switch kind {
        case "edit", "delete", "move": return "Editing files"
        case "execute": return "Running command in terminal"
        case "read": return "Reading files"
        case "search": return "Searching"
        case "fetch": return "Fetching content"
        default: return "Using tool"
        }
    }
}

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
    private var lifecycle = ACPProcessLifecycle()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var stderr: FileHandle?
    private var decoder = ACPMessageDecoder()
    private var writer = ACPMessageWriter()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<ACPMessage, Error>] = [:]
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
    private(set) var supportsImages = false
    var authenticationRequired = false
    var loginURL: URL?
    var onOpenLoginURL: (@MainActor (URL) -> Bool)?
    var onTerminalLogin: (@MainActor (TerminalLoginCommand) async throws -> Void)?
    private var launchAgent: InstalledAgent?
    private var agentName = "Agent"
    private var authenticationRequestID: Int?
    private var openedLoginURLs: Set<URL> = []
    var onText: ((String) -> Void)?
    var onTitle: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var toolActivities: [ACPToolActivity] = []
    var currentToolActivity: ACPToolActivity? { toolActivities.last(where: \.isActive) }
    var activitySummary: String? {
        let active = toolActivities.filter(\.isActive)
        return active.isEmpty ? nil : active.map(\.label).joined(separator: " · ")
    }
    var activityPhase: String? {
        var seen = Set<String>()
        let phases = toolActivities.filter(\.isActive).map(\.phase).filter { seen.insert($0).inserted }
        return phases.isEmpty ? nil : phases.joined(separator: " · ")
    }
    
    func connect(_ agent: InstalledAgent, workspace: URL) async throws {
        close()
        let token = generation
        let agent = try await Self.launchConfiguration(agent)
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        self.workspace = workspace
        launchAgent = agent
        agentName = agent.name
        let child = Process()
        child.executableURL = URL(fileURLWithPath: agent.executable)
        child.arguments = agent.arguments
        child.currentDirectoryURL = workspace
        child.environment = agent.processEnvironment()
        let stdin = Pipe()
        let stdout = Pipe()
        let errors = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = errors
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        stderr = errors.fileHandleForReading
        let decoder = decoder
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            decoder.receive(data) { [weak self] result in
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let messages):
                    for message in messages {
                        guard self.generation == token else { return }
                        self.receive(message.object)
                    }
                case .failure(let error): self.close(reason: error.localizedDescription)
                }
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
        let lifecycle = lifecycle
        do {
            try await lifecycle.start(child)
            guard token == generation else {
                lifecycle.dispose(child, input: stdin.fileHandleForWriting, output: stdout.fileHandleForReading, stderr: errors.fileHandleForReading)
                throw CancellationError()
            }
            try Task.checkCancellation()
            let result = try await request(
                "initialize",
                [
                    "protocolVersion": 1,
                    "clientCapabilities": [
                        "fs": ["readTextFile": false, "writeTextFile": false], "terminal": false,
                        "session": ["configOptions": ["boolean": [:]]],
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
            let capabilities = result["agentCapabilities"] as? [String: Any]
            supportsImages = (capabilities?["promptCapabilities"] as? [String: Any])?["image"] as? Bool == true
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
            if option.kind == .boolean {
                params["type"] = "boolean"
                params["value"] = value == "true"
            } else {
                params["value"] = value
            }
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
        toolActivities = []
        let token = generation
        defer { if generation == token { toolActivities = [] } }
        try await prepareSession()
        guard let sessionID else { throw AppFailure("The agent session is not ready.") }
        let blocks = try await Self.promptBlocks(text, previousMessages: previousMessages,
                                                attachments: attachments, supportsImages: supportsImages)
        guard token == generation else { throw CancellationError() }
        try Task.checkCancellation()
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
        supportsImages = false
        toolActivities = []
        generation = UUID()
        cancellationDeadline?.cancel()
        cancellationDeadline = nil
        resolvePermission(nil)
        output?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process { lifecycle.dispose(process, input: input, output: output, stderr: stderr) }
        lifecycle = ACPProcessLifecycle()
        process = nil
        input = nil
        output = nil
        stderr = nil
        decoder = ACPMessageDecoder()
        writer = ACPMessageWriter()
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
        let message: ACPMessage = try await withCheckedThrowingContinuation { continuation in
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
        return message.object
    }
    private func write(_ object: [String: Any]) throws {
        guard let input else { throw AppFailure("Agent is disconnected.") }
        let token = generation
        writer.write(ACPMessage(object: object), to: input) { [weak self] error in
            guard let self, self.generation == token else { return }
            self.close(reason: "Could not write to the agent: \(error.localizedDescription)")
        }
    }
    private func receive(_ message: [String: Any]) {
        if let method = message["method"] as? String {
            let params = message["params"] as? [String: Any] ?? [:]
            if method == "elicitation/create", let rpcID = message["id"] {
                handleLoginElicitation(params, rpcID: rpcID)
            } else if method == "elicitation/complete" {
                // The authenticate response confirms success; navigation alone never does.
            } else if method == "session/update", let update = params["update"] as? [String: Any] {
                // A replaced session may still emit late notifications.
                guard let sessionID, params["sessionId"] as? String == sessionID else { return }
                if update["sessionUpdate"] as? String == "agent_message_chunk",
                   let content = update["content"] as? [String: Any], let text = content["text"] as? String
                {
                    onText?(text)
                } else if ["tool_call", "tool_call_update"].contains(update["sessionUpdate"] as? String ?? ""),
                          let id = update["toolCallId"] as? String {
                    if let index = toolActivities.firstIndex(where: { $0.id == id }) {
                        var activity = toolActivities[index]
                        activity.merge(update)
                        if activity != toolActivities[index] { toolActivities[index] = activity }
                    } else {
                        var activity = ACPToolActivity(id: id)
                        activity.merge(update)
                        toolActivities.append(activity)
                    }
                } else if update["sessionUpdate"] as? String == "config_option_update" {
                    let options = ACPSessionOption.decode(update)
                    if options != sessionOptions { sessionOptions = options }
                } else if update["sessionUpdate"] as? String == "current_mode_update",
                          let mode = update["currentModeId"] as? String,
                          let index = sessionOptions.firstIndex(where: { $0.transport == .mode }),
                          sessionOptions[index].currentValue != mode
                {
                    sessionOptions[index].currentValue = mode
                } else if update["sessionUpdate"] as? String == "session_info_update",
                          let title = update["title"] as? String {
                    onTitle?(title)
                } else if let title = update["title"] as? String {
                    onStatus?(title)
                }
            } else if method == "session/request_permission", let rpcID = message["id"] {
                guard permission == nil else {
                    try? write([
                        "jsonrpc": "2.0", "id": rpcID, "result": ["outcome": ["outcome": "cancelled"]],
                    ])
                    return
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
                continuation.resume(returning: ACPMessage(object: message["result"] as? [String: Any] ?? [:]))
            }
        }
    }
    @concurrent private static func launchConfiguration(_ agent: InstalledAgent) async throws -> InstalledAgent {
        try agent.acpLaunch()
    }

    @concurrent private static func promptBlocks(
        _ text: String, previousMessages: [ChatMessage], attachments: [ChatAttachment], supportsImages: Bool
    ) async throws -> [[String: String]] {
        guard supportsImages || !(attachments + previousMessages.flatMap { $0.attachments ?? [] }).contains(where: \.isImage) else {
            throw AppFailure("This agent does not support image attachments.")
        }
        var blocks: [[String: String]] = []
        let earlierImages = previousMessages.flatMap { ($0.attachments ?? []).filter(\.isImage) }
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
        blocks += ChatAttachment.promptBlocks(earlierImages)
        blocks += ChatAttachment.promptBlocks(attachments)
        if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
        return blocks
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

/// Only immutable JSON values cross queues. Callers must not put mutable
/// Foundation containers or arbitrary reference types in these internal messages.
struct ACPMessage: @unchecked Sendable {
    let object: [String: Any]
}

/// Owns framing state on one serial queue. Deliver batches in wire order on the
/// main queue so session state changes and response continuations stay ordered.
final class ACPMessageDecoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.onecap.acp.decode", qos: .userInitiated)
    private var buffer = Data()
    private var failed = false

    func receive(_ data: Data, completion: @escaping @MainActor @Sendable (Result<[ACPMessage], Error>) -> Void) {
        queue.async { [self] in
            guard !failed, !data.isEmpty else { return }
            buffer.append(data)
            guard buffer.count <= 16 * 1024 * 1024 else {
                failed = true
                buffer.removeAll()
                DispatchQueue.main.async { completion(.failure(AppFailure("Agent sent an oversized message."))) }
                return
            }
            var messages: [ACPMessage] = []
            // Scan once and discard the consumed prefix once per batch. Removing
            // it for every line repeatedly copies the rest of a large chunk.
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 10) {
                if let object = (try? JSONSerialization.jsonObject(with: Data(buffer[start..<newline]))) as? [String: Any] {
                    messages.append(ACPMessage(object: object))
                }
                start = buffer.index(after: newline)
            }
            buffer.removeSubrange(..<start)
            let batch = messages
            DispatchQueue.main.async { completion(.success(batch)) }
        }
    }
}

/// Pipe writes can block when the child is busy. A per-connection queue preserves
/// request/notification order without holding the UI or cooperative executor.
final class ACPMessageWriter: Sendable {
    private let queue = DispatchQueue(label: "dev.onecap.acp.write", qos: .userInitiated)

    func write(_ message: ACPMessage, to input: FileHandle,
               onError: @escaping @MainActor @Sendable (Error) -> Void) {
        queue.async {
            do {
                var data = try JSONSerialization.data(withJSONObject: message.object)
                data.append(10)
                try input.write(contentsOf: data)
            } catch {
                DispatchQueue.main.async { onError(error) }
            }
        }
    }
}

/// Launch and cleanup share a serial queue, so disconnecting while Process.run
/// is in flight cannot clean up the child before it has started.
private final class ACPProcessLifecycle: Sendable {
    private let queue = DispatchQueue(label: "dev.onecap.acp.process", qos: .utility)

    // Process launch and teardown may block in Foundation; use utility threads rather
    // than the main actor or Swift's cooperative executor.
    func start(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try process.run() })
            }
        }
    }

    func dispose(_ process: Process, input: FileHandle?, output: FileHandle?, stderr: FileHandle?) {
        queue.async {
            if process.isRunning { process.terminate() }
            try? input?.close()
            try? output?.close()
            try? stderr?.close()
        }
    }

}
