import Foundation

struct ProviderClient: ProviderResponding {
    static func endpoint(_ base: String) throws -> URL {
        guard let url = URL(string: base), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
                else {
            throw AppFailure("Enter an HTTPS API base URL without credentials, a query, or a fragment.")
        }
        return url.appendingPathComponent("chat/completions")
    }
    @concurrent func reply(provider: Provider, key: String, messages: [ChatMessage]) async throws
    -> String
    {
        var request = URLRequest(url: try Self.endpoint(provider.baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": provider.model, "stream": false,
            "messages": messages.filter(\.hasContent).map {
                ["role": $0.role, "content": $0.contentForModel]
            },
        ])
        // Do not forward credentials to a redirected endpoint.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppFailure("Invalid provider response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppFailure(
                "Provider returned HTTP \(http.statusCode). Check the endpoint, model, API key, and account balance."
            )
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw AppFailure("The provider did not return a text response.")
        }
        return text
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
