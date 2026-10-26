// Compile against the app’s Debug module and debug dylib, as with the other UI scripts.
import AppKit
import DLS
import Observation
import SwiftUI
@testable import OneCap

@MainActor @Observable final class StreamingState {
    var messages = [ChatMessage(role: "user", text: "Stream a reply"), ChatMessage(role: "assistant", text: "Starting")]
    var edit = ""
}
struct Fixture: View {
    @Bindable var state: StreamingState
    var body: some View {
        ChatTranscript(messages: state.messages, editableMessageID: nil, editingMessageID: nil,
                       editedText: $state.edit, canResend: false, beginEdit: { _ in }, saveEdit: {}, cancelEdit: {})
    }
}
@main struct VerifyTranscriptStreaming {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let renderer = ChatMessageRenderCoordinator()
        var published: [String] = []
        let publish: @MainActor (ChatMarkdown.RenderedMessage) -> Void = { result in
            let text = result.blocks.compactMap { block -> String? in
                guard case .prose(let segments) = block else { return nil }
                return segments.map { String($0.text.characters) }.joined()
            }.joined()
            published.append(text)
        }
        for index in 0..<300 { renderer.update("chunk \(index)", publish: publish) }
        precondition(published.isEmpty, "Rendering must not publish during the view update")
        for _ in 0..<100 where published.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        precondition(published == ["chunk 299"], "Only the latest render may publish")
        renderer.update("chunk 299", publish: publish)
        try await Task.sleep(for: .milliseconds(30))
        precondition(published.count == 1, "Repeated layout must not restart rendering")
        renderer.update("cancelled", publish: publish)
        renderer.cancel()
        try await Task.sleep(for: .milliseconds(30))
        precondition(published.count == 1, "A removed view must not publish")
        renderer.update("chunk 299", publish: publish)
        for _ in 0..<100 where published.count == 1 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(published == ["chunk 299", "chunk 299"], "Reappearing views must resume rendering")
        renderer.cancel()

        let state = StreamingState()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Fixture(state: state).environment(AppStore(stateURL: URL(fileURLWithPath: "/tmp/OneCap-stream-fixture/state.json"))).dlsAppearance(.dark))
        window.contentView = host
        defer { window.close() }
        for index in 0..<300 {
            state.messages[1].text += " chunk \(index)"
            host.layoutSubtreeIfNeeded()
            if index % 20 == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        print("Verified burst coalescing, duplicate suppression, render cancellation, reappearance, and 300 streamed transcript updates.")
    }
}
