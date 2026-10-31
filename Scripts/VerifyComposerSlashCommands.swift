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
        await store.historySaveTask?.value
        print("Verified slash autocomplete, arrow selection, Return, Tab, model changes, command removal, and Escape to literal text.")
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
