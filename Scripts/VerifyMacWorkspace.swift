import AppKit
import DLS
import SwiftUI
@testable import OneCap

/// Render only local fixture data, without opening the user's workspace or contacting a provider.
@main struct VerifyMacWorkspace {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-mac-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        store.loaded = true
        store.historyLoaded = true
        store.projectsLoaded = true
        store.catalogLoaded = true
        store.chatUsesAgent = false
        store.conversations = [0, -1, -3, -12, -45].map { day in
            ChatConversation(id: UUID(), messages: [], draft: "Example conversation \(day)", usesAgent: false,
                             updatedAt: Calendar.current.date(byAdding: .day, value: day, to: .now)!)
        }
        for (name, appearance, size) in [
            ("light", DLSAppearance.light, NSSize(width: 1180, height: 800)),
            ("dark", .dark, NSSize(width: 1180, height: 800)),
            ("light-compact", .light, NSSize(width: 900, height: 680)),
            ("dark-compact", .dark, NSSize(width: 900, height: 680))
        ] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: ContentView().environment(store).dlsAppearance(appearance))
            host.appearance = NSAppearance(named: name.hasPrefix("light") ? .aqua : .darkAqua)
            window.contentView = host
            for _ in 0..<15 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
            precondition(window.toolbar?.allowsUserCustomization == true, "Toolbar customization must be enabled")
            let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
            precondition(identifiers.contains("toggle-chat-changes"), "Files toggle must be available")
            precondition(identifiers.contains("reload-agent"), "Reload must be available")
            if let toolbar = window.toolbar,
               let allowed = toolbar.delegate?.toolbarAllowedItemIdentifiers?(toolbar) {
                precondition(allowed.contains { $0.rawValue == "reload-agent" })
                precondition(allowed.contains { $0.rawValue == "toggle-chat-changes" })
            }
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: "/tmp/OneCap-mac-workspace-\(name).png"))
            }
            window.close()
            print("Verified \(name) workspace and customizable toolbar")
        }

        let searchWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        searchWindow.isReleasedWhenClosed = false
        let searchHost = NSHostingView(rootView:
            ToolbarSearchField(text: .constant(""), prompt: "Search chats", focusRequest: 1))
        searchWindow.contentView = searchHost
        for _ in 0..<10 {
            searchHost.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        func searchField(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        guard let search = searchField(in: searchHost) else { preconditionFailure("Missing native search field") }
        precondition(search.currentEditor() != nil, "Search request must focus the native field")
        searchWindow.close()
        print("Verified native search focus")
    }
}
