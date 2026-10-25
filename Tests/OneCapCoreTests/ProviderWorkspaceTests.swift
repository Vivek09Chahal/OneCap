import Foundation
import Testing
@testable import OneCapCore

private func providerWorkspaceFixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-provider-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "Workspace source text".write(to: root.appendingPathComponent("source.swift"), atomically: true, encoding: .utf8)
    return root
}

@Test func providerWorkspaceReadsSelectedFolderAndRejectsEscapes() throws {
    let root = try providerWorkspaceFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = ProviderWorkspace(root: root)
    #expect(try files.execute(name: "list_directory", arguments: #"{"path":"."}"#).contains("source.swift"))
    #expect(try files.execute(name: "read_file", arguments: #"{"path":"source.swift"}"#) == "Workspace source text")
    let absolute = String(decoding: try JSONEncoder().encode(["path": root.appendingPathComponent("source.swift").path]), as: UTF8.self)
    #expect(try files.execute(name: "read_file", arguments: absolute) == "Workspace source text")
    #expect(throws: AppFailure.self) { try files.execute(name: "read_file", arguments: #"{"path":"../outside.txt"}"#) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root.deletingLastPathComponent())
    #expect(throws: AppFailure.self) { try files.execute(name: "list_directory", arguments: #"{"path":"escape"}"#) }
    #expect(throws: AppFailure.self) { try files.execute(name: "read_file", arguments: #"{"path":"."}"#) }
    try Data(repeating: 65, count: ProviderWorkspace.maximumReadBytes + 1).write(to: root.appendingPathComponent("large"))
    #expect(throws: AppFailure.self) { try files.execute(name: "read_file", arguments: #"{"path":"large"}"#) }
    try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary"))
    #expect(throws: AppFailure.self) { try files.execute(name: "read_file", arguments: #"{"path":"binary"}"#) }
}

private actor WorkspaceProviderServer {
    var requests = 0
    let folderSelected: Bool
    init(folderSelected: Bool) { self.folderSelected = folderSelected }

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        requests += 1
        let message: [String: Any]
        if folderSelected && requests == 1 {
            #expect((body["tools"] as? [Any])?.count == 2)
            #expect((messages.first?["content"] as? String)?.contains("selected this workspace") == true)
            message = ["tool_calls": [
                ["id": "list", "type": "function", "function": ["name": "list_directory", "arguments": #"{"path":"."}"#]],
                ["id": "read", "type": "function", "function": ["name": "read_file", "arguments": #"{"path":"source.swift"}"#]],
                ["id": "escape", "type": "function", "function": ["name": "read_file", "arguments": #"{"path":"../secret"}"#]]
            ]]
        } else {
            if folderSelected {
                let results = messages.filter { ($0["role"] as? String) == "tool" }
                #expect(results.count == 3)
                #expect((results[0]["content"] as? String)?.contains("source.swift") == true)
                #expect(results[1]["content"] as? String == "Workspace source text")
                #expect((results[2]["content"] as? String)?.contains("Access is limited") == true)
                #expect(results.map { $0["tool_call_id"] as? String } == ["list", "read", "escape"])
            } else {
                #expect(body["tools"] == nil)
                #expect(messages.count == 1)
            }
            message = ["content": "Read the selected folder."]
        }
        return (try JSONSerialization.data(withJSONObject: ["choices": [["message": message]]]),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func providerChatExecutesWorkspaceToolsAndContinuesToFinalAnswer() async throws {
    let root = try providerWorkspaceFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let server = WorkspaceProviderServer(folderSelected: true)
    let client = ProviderClient(transport: { try await server.respond($0) })
    let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
    let response = try await client.reply(provider: provider, key: "test", messages: [.init(role: "user", text: "Inspect folder")], workspace: root)
    #expect(response == "Read the selected folder.")
    #expect(await server.requests == 2)
}

@Test func providerChatWithoutFolderKeepsTextOnlyRequests() async throws {
    let server = WorkspaceProviderServer(folderSelected: false)
    let client = ProviderClient(transport: { try await server.respond($0) })
    let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
    _ = try await client.reply(provider: provider, key: "test", messages: [.init(role: "user", text: "Hello")])
    #expect(await server.requests == 1)
}

@Test func providerHTTPFailureIncludesServerMessageAndRedactsKey() async throws {
    let client = ProviderClient(transport: { request in
        let data = Data(#"{"error":{"message":"Model unavailable for secret-test-key\nChoose another model."}}"#.utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    })
    let provider = Provider(name: "Test", baseURL: "https://example.invalid/v1", model: "test")
    do {
        _ = try await client.reply(provider: provider, key: "secret-test-key", messages: [.init(role: "user", text: "Hello")])
        Issue.record("Expected provider failure")
    } catch {
        #expect(error.localizedDescription.contains("HTTP 404"))
        #expect(error.localizedDescription.contains("Model unavailable for [redacted] Choose another model."))
        #expect(!error.localizedDescription.contains("secret-test-key"))
    }
}
