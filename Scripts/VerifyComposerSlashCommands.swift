// Compile against the app's Debug module and debug dylib, as with the other UI verification scripts.
import AppKit
import DLS
import SwiftUI
@testable import OneCap

private struct SlashFixture: View {
    @Environment(AppStore.self) private var store
    let sent: () -> Void
    var body: some View {
        @Bindable var store = store
        VStack {
            Spacer()
            ChatComposer(draft: $store.draft, sending: false, stopping: false, canSend: true,
                send: sent, stop: {}, leading: { EmptyView() }, trailing: { EmptyView() })
        }.padding().frame(width: 600, height: 500)
    }
}

@main struct VerifyComposerSlashCommands {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-slash-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        store.chatUsesAgent = false
        store.providers = [
            .init(name: "First", baseURL: "https://example.com/v1", model: "first-model"),
            .init(name: "Second", baseURL: "https://example.com/v1", model: "second-model"),
        ]
        store.selectedProviderID = store.providers[0].id
        var sends = 0
        let host = NSHostingView(rootView: SlashFixture(sent: { sends += 1 }).environment(store).dlsAppearance(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        guard let editor = editor(in: host) else { throw AppFailure("Missing native composer") }
        window.makeFirstResponder(editor)
        await settle()
        editor.insertText("/", replacementRange: editor.selectedRange())
        await settle()
        key(48, "\t", editor: editor, window: window)
        await settle()
        precondition(store.draft == "/model ", "Tab must autocomplete the command without sending")
        key(125, "", editor: editor, window: window)
        await settle()
        key(36, "\r", editor: editor, window: window)
        await settle()
        precondition(store.selectedProviderID == store.providers[1].id, "Arrows and Return must choose a model")
        precondition(store.draft.isEmpty && sends == 0, "Slash commands must not reach chat")
        editor.insertText("/model first", replacementRange: editor.selectedRange())
        await settle()
        key(48, "\t", editor: editor, window: window)
        await settle()
        precondition(store.selectedProviderID == store.providers[0].id, "Filtered autocomplete must accept Tab")
        precondition(store.draft.isEmpty && sends == 0)
        editor.insertText("/literal", replacementRange: editor.selectedRange())
        await settle()
        key(53, "", editor: editor, window: window)
        await settle()
        key(36, "\r", editor: editor, window: window)
        await settle()
        precondition(sends == 1 && store.draft == "/literal", "Escape must allow literal slash text")
        for (before, after) in [("", "Existing text"), ("Before 👋🏽 ", "after"), ("Existing text ", ""),
                                ("First line\nMore text ", " next line\nKeep this too")] {
            editor.insertText(before + after, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            await settle()
            editor.setSelectedRange(NSRange(location: (before as NSString).length, length: 0))
            await settle()
            editor.insertText("/mo", replacementRange: editor.selectedRange())
            await settle()
            key(48, "\t", editor: editor, window: window)
            await settle()
            precondition(store.draft == before + "/model " + after, "Autocomplete must preserve surrounding text")
            precondition(editor.selectedRange().location == (before + "/model " as NSString).length,
                "Autocomplete must keep the caret at the command, including after emoji")
            editor.insertText("first", replacementRange: editor.selectedRange())
            await settle()
            key(36, "\r", editor: editor, window: window)
            await settle()
            precondition(store.draft == before + after && sends == 1,
                "Executing an inline command must remove only the command and never send the draft")
            precondition(editor.selectedRange().location == (before as NSString).length,
                "Executing a command must preserve the insertion position")
            editor.insertText("/attach", replacementRange: editor.selectedRange())
            await settle()
            key(48, "\t", editor: editor, window: window)
            await settle()
            precondition(store.draft == before + "/attach " + after,
                "Attachment commands must work before, between, and after text")
            key(53, "", editor: editor, window: window)
            await settle()
        }
        store.messages = [.init(role: "user", text: "Keep previous chat")]
        let previousConversation = store.conversationID
        editor.insertText("/clear", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await settle()
        key(36, "\r", editor: editor, window: window)
        await settle()
        precondition(store.conversationID != previousConversation && store.messages.isEmpty && store.draft.isEmpty,
            "/clear + Return must open a fresh chat")
        precondition(store.conversations.first(where: { $0.id == previousConversation })?.messages.first?.text == "Keep previous chat",
            "/clear must preserve the previous conversation")
        precondition(sends == 1, "/clear must not be sent to the provider")
        let freshConversation = store.conversationID
        editor.insertText("/clear ", replacementRange: editor.selectedRange())
        await settle()
        key(48, "\t", editor: editor, window: window)
        await settle()
        precondition(store.conversationID != freshConversation && store.draft.isEmpty && sends == 1,
            "/clear with trailing whitespace must also work through Tab")
        await store.historySaveTask?.value
        print("Verified commands before, between, and after text, including emoji, multiline drafts, attachment autocomplete, caret preservation, and /clear.")
    }

    @MainActor private static func editor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
    @MainActor private static func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
    @MainActor private static func key(_ code: UInt16, _ characters: String, editor: NSTextView, window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        editor.keyDown(with: event)
    }
}
