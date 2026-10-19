import Foundation

/// Runs blocking pipe reads on a utility thread, outside Swift's cooperative executor.
struct ProcessRunner: ProcessRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil)
    async throws -> String
    {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(
                        with: Result {
                            try execution.run(executable, arguments, environment: environment)
                        })
                }
            }
        } onCancel: {
            execution.cancel()
        }
    }
}

/// The lock protects process ownership and cancellation across the task and utility thread.
private final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    
    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }
    
    func run(_ executable: String, _ arguments: [String], environment: [String: String]?) throws
    -> String
    {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.environment = environment
        let output = Pipe()
        child.standardOutput = output
        child.standardError = output
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            process = child
            try child.run()
        }
        defer { lock.withLock { process = nil } }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        try lock.withLock {
            if cancelled { throw CancellationError() }
        }
        guard child.terminationStatus == 0 else {
            throw AppFailure(
                "Package operation failed (exit \(child.terminationStatus)). Check your connection and the agent’s installation requirements."
            )
        }
        return String(decoding: data, as: UTF8.self)
    }
}
