import Foundation

/// Shared across windows. Each operation snapshots these values when it starts.
struct RequestSettings: Sendable {
    enum Limit: String, CaseIterable, Sendable {
        case connection, agentResponse, providerResponse, authentication, cancellation, download, skillDownload
        case retryCount, retryDelay

        var key: String { "requests.\(rawValue)" }
        var defaultValue: Int {
            switch self {
            case .connection: 60
            case .agentResponse: 600
            case .providerResponse: 120
            case .authentication: 300
            case .cancellation: 10
            case .download: 180
            case .skillDownload: 30
            case .retryCount: 0
            case .retryDelay: 5
            }
        }
        var range: ClosedRange<Int> {
            switch self {
            case .retryCount: 0...10
            case .retryDelay: 1...300
            case .cancellation: 1...120
            default: 10...7200
            }
        }
    }

    private let values: [Limit: Int]

    init(defaults: UserDefaults = .standard) {
        values = Dictionary(uniqueKeysWithValues: Limit.allCases.map { limit in
            let saved = (defaults.object(forKey: limit.key) as? NSNumber)?.doubleValue
            let value = saved.flatMap { $0.isFinite ? $0 : nil } ?? Double(limit.defaultValue)
            return (limit, Int(min(max(value, Double(limit.range.lowerBound)), Double(limit.range.upperBound))))
        })
    }

    subscript(_ limit: Limit) -> Int { values[limit] ?? limit.defaultValue }

    func pauseBeforeRetry() async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(self[.retryDelay]))
        try Task.checkCancellation()
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    static func isTransientConnection(_ error: Error) -> Bool {
        if isTransient(error) { return true }
        let message = error.localizedDescription
        return message.hasPrefix("Agent request timed out.") || message.hasPrefix("Agent exited (")
            || message.hasPrefix("Could not write to the agent:") || message == "Agent is disconnected."
    }

    /// GET requests are safe to repeat. Provider POSTs only repeat explicit temporary rejections.
    func data<Value>(for request: URLRequest,
                     transport: (URLRequest) async throws -> (Value, URLResponse)) async throws -> (Value, URLResponse) {
        for attempt in 0...self[.retryCount] {
            try Task.checkCancellation()
            do {
                let result = try await transport(request)
                try Task.checkCancellation()
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                let retryable = request.httpMethod == "GET"
                    ? [408, 429, 500, 502, 503, 504].contains(status)
                    : [429, 503].contains(status)
                if !retryable || attempt == self[.retryCount] { return result }
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                guard request.httpMethod == "GET", Self.isTransient(error), attempt < self[.retryCount] else {
                    throw error
                }
            }
            try await pauseBeforeRetry()
        }
        throw CancellationError() // The bounded loop always returns or throws above.
    }
}
