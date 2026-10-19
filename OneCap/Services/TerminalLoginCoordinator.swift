import Foundation
import Observation

@MainActor @Observable final class TerminalLoginSession: Identifiable {
    let id = UUID()
    let command: TerminalLoginCommand
    private(set) var finished = false
    private(set) var loginURL: URL?
    @ObservationIgnored var terminateProcess: (() -> Void)?
    @ObservationIgnored private var completion: ((Result<Void, Error>) -> Void)?
    @ObservationIgnored private var output = Data()
    @ObservationIgnored private var openedURLs: Set<URL> = []
    @ObservationIgnored private let openURL: @MainActor (URL) -> Bool
    
    init(
        command: TerminalLoginCommand, openURL: @escaping @MainActor (URL) -> Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.command = command
        self.openURL = openURL
        self.completion = completion
    }
    
    func complete(exitCode: Int32?) {
        guard !finished else { return }
        if exitCode == 0 {
            finish(.success(()))
        } else {
            finish(
                .failure(
                    AppFailure(
                        "Terminal sign-in did not succeed (status \(exitCode.map(String.init) ?? "unavailable")). Try again."
                    )))
        }
    }
    
    func cancel() {
        guard !finished else { return }
        terminateProcess?()
        finish(.failure(CancellationError()))
    }
    
    private func finish(_ result: Result<Void, Error>) {
        finished = true
        terminateProcess = nil
        let callback = completion
        completion = nil
        output.removeAll()
        callback?(result)
    }
    
    /// Inspect complete output lines for login links. The terminal itself owns rendering and input.
    func consumeOutput(_ data: Data) {
        guard !finished else { return }
        output.append(data)
        while let end = output.firstIndex(of: 10) {
            let line = String(decoding: output[..<end], as: UTF8.self)
            output.removeSubrange(...end)
            let lower = line.lowercased()
            guard
                ["login", "log in", "sign in", "auth", "browser", "visit", "verify", "open"].contains(
                    where: lower.contains),
                let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                    else { continue }
            for match in detector.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let raw = match.url?.absoluteString, let url = LoginURL.validated(raw) { openLink(url) }
            }
        }
        if output.count > 16384 { output = Data(output.suffix(8192)) }
    }
    
    func openLink(_ url: URL) {
        guard !finished, let url = LoginURL.validated(url.absoluteString) else { return }
        loginURL = url
        if !openedURLs.contains(url), openURL(url) { openedURLs.insert(url) }
    }
}

@MainActor @Observable final class TerminalLoginCoordinator {
    private(set) var session: TerminalLoginSession?
    @ObservationIgnored private let openURL: @MainActor (URL) -> Bool
    
    init(openURL: @escaping @MainActor (URL) -> Bool = LoginBrowser.open) { self.openURL = openURL }
    
    func run(_ command: TerminalLoginCommand) async throws {
        cancel()
        let requestID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                currentRequestID = requestID
                session = TerminalLoginSession(command: command, openURL: openURL) { [weak self] result in
                    if self?.currentRequestID == requestID {
                        self?.session = nil
                        self?.currentRequestID = nil
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.currentRequestID == requestID { self?.cancel() }
            }
        }
    }
    
    @ObservationIgnored private var currentRequestID: UUID?
    func cancel() { session?.cancel() }
}
