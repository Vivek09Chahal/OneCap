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
        // A wheel gesture must suspend following while the answer continues growing.
        state.messages[1].text = (0..<160).map { "Line \($0): streamed answer text." }.joined(separator: "\n\n")
        for _ in 0..<25 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        guard let scroll = scrollView(in: host) else { fatalError("Missing transcript scroll view") }
        func wheel(_ delta: Int32, phase: CGScrollPhase) {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: delta, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            if let native = NSEvent(cgEvent: event) { scroll.scrollWheel(with: native) }
        }
        wheel(0, phase: .began)
        for _ in 0..<30 {
            wheel(-100, phase: .changed)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        wheel(0, phase: .ended)
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let bottom = scroll.contentView.bounds.minY
        wheel(300, phase: .began)
        for _ in 0..<8 {
            wheel(150, phase: .changed)
            try await Task.sleep(for: .milliseconds(20))
        }
        wheel(0, phase: .ended)
        try await Task.sleep(for: .milliseconds(150))
        let readingPosition = scroll.contentView.bounds.minY
        precondition(abs(readingPosition - bottom) > 100, "Wheel must move away from the latest reply")
        for index in 0..<30 {
            state.messages[1].text += "\n\nMore streamed text \(index)."
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(150))
        precondition(scroll === scrollView(in: host), "Transcript scroll view must retain its identity")
        precondition(abs(scroll.contentView.bounds.minY - readingPosition) < 20,
                     "Streaming must preserve the user's reading position")
        // Move the native scrollbar to the bottom, independent of wheel acceleration.
        let bottomOrigin = max(0, scroll.documentView!.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottomOrigin))
        scroll.reflectScrolledClipView(scroll.contentView)
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let resumedPosition = scroll.contentView.bounds.minY
        for index in 0..<15 {
            state.messages[1].text += "\n\nNew text at bottom \(index)."
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        precondition(scroll.contentView.bounds.minY > resumedPosition + 100,
                     "Returning to the bottom must resume following new output")
        print("Verified free wheel scrolling, stable reading position, and resumed following at the bottom.")
        print("Verified burst coalescing, duplicate suppression, render cancellation, reappearance, and 300 streamed transcript updates.")
    }
}
