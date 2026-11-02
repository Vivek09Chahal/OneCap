import Foundation
import Testing
@testable import OneCapCore

private func requestPreferences() -> (String, UserDefaults) {
    let name = "OneCap-requests-test-\(UUID())"
    return (name, UserDefaults(suiteName: name)!)
}

@Test func requestSettingsPreserveDefaultsAndClampSavedValues() {
    let (name, defaults) = requestPreferences()
    defer { defaults.removePersistentDomain(forName: name) }
    let original = RequestSettings(defaults: defaults)
    #expect(original[.agentResponse] == 600)
    #expect(original[.providerResponse] == 120)
    #expect(original[.retryCount] == 0)
    defaults.set(3600, forKey: RequestSettings.Limit.agentResponse.key)
    defaults.set(-1, forKey: RequestSettings.Limit.retryCount.key)
    defaults.set(99999, forKey: RequestSettings.Limit.download.key)
    let changed = RequestSettings(defaults: defaults)
    #expect(changed[.agentResponse] == 3600)
    #expect(changed[.retryCount] == 0)
    #expect(changed[.download] == 7200)
    #expect(original[.agentResponse] == 600)
}

@Test func requestRetriesAreBoundedAndOnlyRepeatSafeFailures() async throws {
    let (name, defaults) = requestPreferences()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(1, forKey: RequestSettings.Limit.retryCount.key)
    defaults.set(1, forKey: RequestSettings.Limit.retryDelay.key)
    let settings = RequestSettings(defaults: defaults)
    let url = URL(string: "https://example.com/test")!
    for (method, status, expected) in [("GET", 503, 2), ("POST", 429, 2), ("POST", 500, 1), ("GET", 401, 1)] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        var calls = 0
        let (_, response) = try await settings.data(for: request) { _ in
            calls += 1
            return (Data(), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        #expect(calls == expected)
        #expect((response as? HTTPURLResponse)?.statusCode == status)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    var calls = 0
    do {
        let _: (Data, URLResponse) = try await settings.data(for: request) { _ in
            calls += 1
            throw URLError(.timedOut)
        }
        Issue.record("Timed-out POST must not be replayed")
    } catch { #expect((error as? URLError)?.code == .timedOut) }
    #expect(calls == 1)
}

@Test func requestRetriesRecoverFromTransientDownloadFailure() async throws {
    let (name, defaults) = requestPreferences()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(1, forKey: RequestSettings.Limit.retryCount.key)
    defaults.set(1, forKey: RequestSettings.Limit.retryDelay.key)
    let settings = RequestSettings(defaults: defaults)
    let url = URL(string: "https://example.com/test")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    var calls = 0
    let (data, _) = try await settings.data(for: request) { _ in
        calls += 1
        if calls == 1 { throw URLError(.networkConnectionLost) }
        return (Data("complete".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(calls == 2)
    #expect(String(decoding: data, as: UTF8.self) == "complete")
}

@Test func requestRetryDelayCanBeCancelled() async throws {
    let (name, defaults) = requestPreferences()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(10, forKey: RequestSettings.Limit.retryCount.key)
    defaults.set(300, forKey: RequestSettings.Limit.retryDelay.key)
    let settings = RequestSettings(defaults: defaults)
    let task = Task {
        try await settings.pauseBeforeRetry()
    }
    try await Task.sleep(for: .milliseconds(20))
    task.cancel()
    do {
        try await task.value
        Issue.record("Retry delay ignored cancellation")
    } catch { #expect(error is CancellationError) }
    #expect(!RequestSettings.isTransientConnection(AppFailure("This agent does not support ACP v1.")))
    #expect(RequestSettings.isTransientConnection(AppFailure("Agent request timed out. Reconnect to try again.")))
}
