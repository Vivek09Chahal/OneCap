import Foundation
import Darwin

/// One request per process. No host objects or provider credentials cross this bridge.
struct PluginPackageRuntime: Sendable {
    let registry: PluginPackageRegistry

    func execute(_ package: InstalledPluginPackage, kind: String, name: String,
                 arguments: PluginJSON, workspace: URL?) async throws -> String {
        let package = try await registry.approved(package)
        let features = kind == "commands/execute" ? package.manifest.commands : package.manifest.tools
        guard ["commands/execute", "tools/call"].contains(kind),
              features.contains(where: { $0.id == name }), case .object = arguments else {
            throw AppFailure("Unknown plugin feature or invalid arguments.")
        }
        let entrypoint = try package.manifest.validate(in: package.directory)
        let request: PluginJSON = .object([
            "apiVersion": .number(1), "method": .string(kind), "name": .string(name),
            "arguments": arguments, "context": .object(["workspace": workspace.map { .string($0.path) } ?? .null])])
        let input = try JSONEncoder().encode(request)
        guard input.count <= 64 * 1024 else { throw AppFailure("Plugin input exceeds 64 KB.") }
        let execution = PluginPackageExecution()
        let data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result {
                        try execution.run(package: package, entrypoint: entrypoint, input: input)
                    })
                }
            }
        } onCancel: { execution.stop() }
        try Task.checkCancellation()
        let response = try JSONDecoder().decode(PluginJSON.self, from: data)
        guard response["apiVersion"] == .number(1), response["error"] == nil,
              let result = response["result"] else { throw AppFailure("Plugin returned an invalid response or reported a failure.") }
        if let text = result.string { return text }
        return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }
}

private final class PluginPackageExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    func stop() {
        lock.withLock {
            stopped = true
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func run(package: InstalledPluginPackage, entrypoint: URL, input: Data) throws -> Data {
        let child = Process()
        child.executableURL = package.manifest.interpreter.map { URL(fileURLWithPath: $0) } ?? entrypoint
        child.arguments = package.manifest.interpreter == nil ? [] : [entrypoint.path]
        child.currentDirectoryURL = package.directory
        // Deliberately omit inherited API keys, tokens and application configuration.
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                             "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                             "TMPDIR": NSTemporaryDirectory(), "PYTHONDONTWRITEBYTECODE": "1"]
        let output = Pipe(), stdin = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.standardInput = stdin
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            process = child
            try child.run()
        }
        let timeout = DispatchWorkItem { self.stop() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
        defer {
            timeout.cancel()
            stop()
            lock.withLock { process = nil }
            try? output.fileHandleForReading.close()
        }
        // Write concurrently with reading so misbehaving children cannot fill both pipes.
        DispatchQueue.global(qos: .utility).async {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }
        var data = Data()
        let descriptor = output.fileHandleForReading.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            guard !lock.withLock({ stopped }) else { throw AppFailure("Plugin was cancelled or exceeded its 30-second time limit.") }
            var event = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&event, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw AppFailure("Could not read plugin output.")
            }
            if ready == 0 { continue }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw AppFailure("Could not read plugin output.")
            }
            guard data.count + count <= 1024 * 1024 else {
                stop()
                child.waitUntilExit()
                throw AppFailure("Plugin output exceeded 1 MB.")
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        child.waitUntilExit()
        guard !lock.withLock({ stopped }) else { throw AppFailure("Plugin was cancelled or exceeded its 30-second time limit.") }
        guard child.terminationStatus == 0 else { throw AppFailure("Plugin exited with status \(child.terminationStatus).") }
        return data
    }
}
