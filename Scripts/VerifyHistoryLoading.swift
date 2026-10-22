@testable import OneCap
import AppKit
import DLS
import SwiftUI

/// Run against the Debug app module. Uses synthetic history, no agent or provider.
@main struct VerifyHistoryLoading {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-history-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        store.conversations = [2, 80, 6].enumerated().map { chat, count in
            let messages = (0..<count).map { index in
                ChatMessage(role: index.isMultiple(of: 2) ? "user" : "assistant", text:
                    index == count - 1 ? "LATEST MESSAGE IN CHAT \(chat)" :
                    "Message \(index) in chat \(chat). **Saved formatting** and `inline code`.\n\nA paragraph of saved conversation text.")
            }
            return ChatConversation(id: UUID(), messages: messages, draft: "Draft \(chat)",
                usesAgent: false, updatedAt: .now)
        }
        let chats = store.conversations
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ChatView().environment(store).dlsAppearance(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        window.contentView = host
        window.orderOut(nil)
        defer { window.close() }
        for index in [0, 1, 2, 1, 0] {
            let chat = chats[index]
            let start = ContinuousClock.now
            store.openConversation(chat.id)
            guard store.conversationID == chat.id, store.messages.last?.text == "LATEST MESSAGE IN CHAT \(index)",
                  store.draft == "Draft \(index)" else { throw AppFailure("History selection restored the wrong chat") }
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw AppFailure("No transcript rendering")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: "/tmp/OneCap-history-layout-\(index).png"))
            print("Opened chat \(index) (\(chat.messages.count) messages), laid out and captured in \(start.duration(to: .now))")
        }
        guard !store.connecting, !store.acp.connected, store.error == nil else {
            throw AppFailure("History display unexpectedly required an agent connection")
        }
        print("Verified repeated short/long history selection without an agent or provider connection.")
    }
}
