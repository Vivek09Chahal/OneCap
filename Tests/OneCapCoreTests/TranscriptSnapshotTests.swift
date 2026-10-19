import Foundation
import Testing

@testable import OneCapCore

@Test func transcriptRowsKeepTheirTimingWhenAuthenticationRemovesTheReply() {
    let user = ChatMessage(role: "user", text: "Continue")
    let timing = ThinkingTime()
    var messages = [user, ChatMessage(role: "assistant", text: "", thinkingTime: timing)]
    let visibleRows = ChatTranscriptEntry.make(from: messages)
    messages.removeLast()
    #expect(visibleRows.count == 1)
    #expect(visibleRows.first?.thinkingTime?.startedAt == timing.startedAt)
    #expect(ChatTranscriptEntry.make(from: messages).first?.thinkingTime == nil)
    messages.removeAll()
    #expect(visibleRows.first?.message.id == user.id)
    #expect(ChatTranscriptEntry.make(from: messages).isEmpty)
}

@Test func transcriptSnapshotsRemainConsistentAcrossStreamingAndTurnReplacement() {
    let user = ChatMessage(role: "user", text: "Explain this code")
    var messages = [user, ChatMessage(role: "assistant", text: "", thinkingTime: ThinkingTime())]
    for index in 0..<250 {
        messages[1].text += "Streaming chunk \(index). "
        let rendered = ChatTranscriptEntry.make(from: messages)
        #expect(rendered.map(\.id) == messages.map(\.id))
        #expect(rendered[1].message.text == messages[1].text)
        if index % 25 == 0 {
            let retained = rendered
            messages.removeLast()
            messages.append(ChatMessage(role: "assistant", text: "Replacement", thinkingTime: ThinkingTime()))
            #expect(retained[1].id != messages[1].id)
            #expect(ChatTranscriptEntry.make(from: messages)[1].id == messages[1].id)
        }
    }
}

@Test func transcriptOnlyPairsAnAdjacentAssistantWithItsUserMessage() {
    let first = ChatMessage(role: "user", text: "First")
    let second = ChatMessage(role: "user", text: "", attachments: [.init(name: "code.swift", text: "let x = 1")])
    let reply = ChatMessage(role: "assistant", text: "Answer", thinkingTime: ThinkingTime())
    let entries = ChatTranscriptEntry.make(from: [first, second, reply])
    #expect(entries.count == 3)
    #expect(entries[0].thinkingTime == nil)
    #expect(entries[1].thinkingTime?.startedAt == reply.thinkingTime?.startedAt)
    #expect(entries[2].thinkingTime == nil)
}
