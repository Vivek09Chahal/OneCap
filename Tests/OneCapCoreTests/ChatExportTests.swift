import Foundation
import PDFKit
import Testing

@testable import OneCapCore

@Test @MainActor func chatExportPreservesTranscriptAndAttachments() throws {
    let attachment = ChatAttachment(name: "source.swift", text: "let fence = \"```\"")
    let image = ChatAttachment(name: "image.png", text: "", imageData: Data([1, 2, 3]), mimeType: "image/png")
    let messages = [
        ChatMessage(role: "user", text: "Question 日本語", attachments: [attachment, image]),
        ChatMessage(role: "assistant", text: "```swift\nprint(42)\n```", replyState: .stopped),
    ]
    let export = ChatExport(title: "A / chat: title", messages: messages)
    #expect(!export.filename.contains("/"))
    #expect(!export.filename.contains(":"))
    #expect(export.markdown.contains("## You\n\nQuestion 日本語"))
    #expect(export.markdown.contains("````\nlet fence"))
    #expect(export.markdown.contains("Reply status: stopped"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(ChatExport.self, from: export.data(for: .json))
    #expect(restored.version == 1)
    #expect(restored.messages == messages)
    #expect(restored.title == export.title)
    #expect(ChatExport(title: "../", messages: []).filename == "-")
}

@Test @MainActor func chatExportPDFPaginatesWithoutDroppingTail() throws {
    let source = (1...600).map { "Line \($0): long transcript text." }.joined(separator: "\n")
        + "\nFINAL_TRANSCRIPT_MARKER"
    let export = ChatExport(title: "Long chat", messages: [ChatMessage(role: "assistant", text: source)])
    let pdf = try #require(PDFDocument(data: export.data(for: .pdf)))
    #expect(pdf.pageCount > 1)
    let text = try #require(pdf.string)
    #expect(text.contains("Long chat"))
    #expect(text.contains("FINAL_TRANSCRIPT_MARKER"))
}

@Test @MainActor func chatExportUsesLiveMessagesAndExcludesDraftsAndSettings() throws {
    let store = AppStore()
    store.messages = [ChatMessage(role: "user", text: "Sent question")]
    store.checkpointConversation(touch: false)
    store.messages.append(ChatMessage(role: "assistant", text: "Live partial response", replyState: .responding))
    store.draft = "UNSENT_SECRET"
    store.workspace = URL(fileURLWithPath: "/private/WORKSPACE_SECRET")
    let export = store.exportTranscript(store.conversationID)
    #expect(export.messages.count == 2)
    let json = String(decoding: try export.data(for: .json), as: UTF8.self)
    #expect(json.contains("Live partial response"))
    #expect(!json.contains("UNSENT_SECRET"))
    #expect(!json.contains("WORKSPACE_SECRET"))
    #expect(store.messages.last?.replyState == .responding)
}
