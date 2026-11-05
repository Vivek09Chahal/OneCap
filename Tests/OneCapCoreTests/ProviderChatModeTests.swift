import Foundation
import Testing
@testable import OneCapCore

@Test(arguments: ProviderChatMode.allCases)
func providerModeReachesRequest(_ mode: ProviderChatMode) async throws {
    let client = ProviderClient(transport: { request in
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.first?["content"] as? String == mode.instruction)
        #expect(messages.filter { $0["role"] as? String == "system" }.count == 1)
        #expect(messages.last?["content"] as? String == "Current request")
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil))
        return (Data(#"{"choices":[{"message":{"content":"Done"}}]}"#.utf8), response)
    })
    let provider = Provider(name: "Custom", baseURL: "https://example.invalid/v1", model: "custom-model")
    let response = try await client.reply(provider: provider, key: "test", messages: [
        .init(role: "user", text: "Previous request", providerMode: .plan),
        .init(role: "assistant", text: "Previous answer"),
        .init(role: "user", text: "Current request", providerMode: mode)
    ])
    #expect(response == "Done")
}

@Test @MainActor func providerModePersistsWithChatAndQueuedMessages() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-modes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await store.load()
    store.providers = [Provider(name: "Custom", baseURL: "https://example.invalid/v1", model: "custom-model")]
    store.selectedProviderID = store.providers.first?.id
    store.draft = "Draft"
    store.selectProviderMode(.write)
    // Simulate an active turn so submission exercises the real queue path without a network call.
    store.sending = true
    #expect(store.send("Queued code request", useAgent: false))
    store.selectProviderMode(.plan)
    #expect(store.send("Queued planning request", useAgent: false))
    store.sending = false
    let id = store.conversationID
    store.checkpointConversation()
    let saved = try #require(store.conversations.first { $0.id == id })
    let decoded = try JSONDecoder().decode(ChatConversation.self, from: JSONEncoder().encode(saved))
    #expect(decoded.providerMode == .plan)
    #expect(decoded.queuedMessages?.map { $0.message.providerMode } == [.write, .plan])
    store.newChat()
    store.selectProviderMode(.ask)
    store.openConversation(id)
    #expect(store.chatSession.providerMode == .plan)
    #expect(store.queuedMessages.map { $0.message.providerMode } == [.write, .plan])
    await store.historySaveTask?.value
}

@Test func legacyProviderChatHasNoModeOverride() throws {
    let message = try JSONDecoder().decode(ChatMessage.self,
        from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","role":"user","text":"Hello"}"#.utf8))
    #expect(message.providerMode == nil)
    let chat = ChatConversation(id: UUID(), messages: [message], draft: "", usesAgent: false, updatedAt: .now)
    #expect(try JSONDecoder().decode(ChatConversation.self, from: JSONEncoder().encode(chat)).providerMode == nil)
}
