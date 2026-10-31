import AppKit
import DLS
import SwiftUI
@testable import OneCap

@MainActor private final class TypographyObservation {
    var appearance = ChatAppearance()
}

private struct TypographyProbe: View {
    @Environment(\.chatAppearance) private var appearance
    let observation: TypographyObservation

    var body: some View {
        Color.clear.allowsHitTesting(false)
            .onChange(of: appearance, initial: true) { _, value in observation.appearance = value }
    }
}

private struct TypographyFixture: View {
    let theme: DLSTheme
    let store: AppStore
    let observation: TypographyObservation

    var body: some View {
        ChatView().overlay(TypographyProbe(observation: observation))
            .environment(store)
            .chatAppearancePreferences()
            .environment(\.dlsTheme, theme)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Local theme changes verify font propagation and the actual composer width.
@main struct VerifyChatTypographyLayout {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await verify()
                exit(0)
            } catch { fatalError(error.localizedDescription) }
        }
        NSApp.run()
    }

    @MainActor private static func verify() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: DLSVisualPreferences.storageKey)
        let previousChatSize = defaults.object(forKey: "chatFontSize")
        defer {
            defaults.set(previous, forKey: DLSVisualPreferences.storageKey)
            defaults.set(previousChatSize, forKey: "chatFontSize")
        }
        defaults.set(14.0, forKey: "chatFontSize")
        var preferences = DLSVisualPreferences()
        preferences.shared.uiFont = "Helvetica Neue"
        preferences.shared.uiSize = 17
        preferences.shared.uiWeight = "Medium"
        defaults.set(try JSONEncoder().encode(preferences), forKey: DLSVisualPreferences.storageKey)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-chat-font-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        store.loaded = true
        store.chatUsesAgent = false
        store.draft = "The message field follows the app font in a centered column."
        store.messages = [.init(role: "user", text: "Center the chat and message field."),
            .init(role: "assistant", text: "Chat text follows your app font. The conversation and composer share a centered column that fits smaller windows.")]
        let observation = TypographyObservation()
        var theme = DLSTheme.light
        theme.preferences = preferences
        let host = NSHostingView(rootView: TypographyFixture(theme: theme, store: store, observation: observation))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        func settle() async throws {
            for _ in 0..<12 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        func composer(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.string == store.draft { return text }
            return view.subviews.lazy.compactMap { composer(in: $0) }.first
        }
        try await settle()
        precondition(observation.appearance.profile.uiFont == "Helvetica Neue")
        precondition(observation.appearance.textSize == 17)
        guard let editor = composer(in: host) else { fatalError("Missing composer") }
        precondition(editor.font?.familyName == "Helvetica Neue")
        precondition(editor.font?.pointSize == 19)
        for width in [1000, 1500] {
            window.setContentSize(NSSize(width: width, height: 720))
            try await settle()
            let editorWidth = editor.enclosingScrollView?.bounds.width ?? 0
            precondition(editorWidth > ChatLayout.contentMaxWidth - 110
                && editorWidth <= ChatLayout.contentMaxWidth,
                "Composer must stay within the centered chat column")
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/OneCap-chat-wide-\(width).png"))
        }
        preferences.shared.uiFont = "Menlo"
        preferences.shared.uiSize = 18
        preferences.shared.uiWeight = "Bold"
        theme.preferences = preferences
        let updatedHost = NSHostingView(rootView: TypographyFixture(theme: theme, store: store, observation: observation))
        window.contentView = updatedHost
        for _ in 0..<12 {
            updatedHost.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(observation.appearance.profile.uiFont == "Menlo")
        precondition(observation.appearance.textSize == 18)
        guard let updatedEditor = composer(in: updatedHost) else { fatalError("Missing updated composer") }
        precondition(updatedEditor.font?.familyName == "Menlo")
        precondition(updatedEditor.font?.pointSize == 20)
        precondition(observation.appearance.profile.nsFont(size: 18, content: true)
            == observation.appearance.profile.nsFont(size: 18), "Chat inherits the app font weight")
        window.close()
        print("PASS: App font family, size, and weight update chat and composer; bounded layouts verified at 1000 and 1500 points")
    }
}
