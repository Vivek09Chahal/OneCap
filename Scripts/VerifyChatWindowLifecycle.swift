import AppKit
import SwiftUI

@testable import OneCap

// Compile against the app's Debug module and debug dylib.
@main
struct VerifyChatWindowLifecycle {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let windows = ChatWindows()
        let oldID = UUID()
        let currentID = UUID()
        let store = AppStore()
        windows.stores[oldID] = store
        let chat = store.conversationID
        let oldWindow = makeWindow()
        oldWindow.contentView = ChatWindowAttachment.AttachmentView(windows: windows, id: oldID)

        precondition(windows.owner(of: chat, excluding: currentID) == oldID)
        precondition(windows.owner(of: chat, excluding: oldID) == nil)
        precondition(windows.focusChat(chat, excluding: currentID))
        oldWindow.close()

        // AppKit may retain a closed window. Its store must not imply an open owner.
        precondition(windows.stores[oldID] === store)
        precondition(windows.owner(of: chat, excluding: currentID) == nil)
        precondition(!windows.focusChat(chat, excluding: currentID))

        let explicitWindow = makeWindow()
        explicitWindow.contentView = ChatWindowAttachment.AttachmentView(windows: windows, id: oldID)
        precondition(windows.owner(of: chat, excluding: currentID) == oldID)
        precondition(windows.focusChat(chat, excluding: currentID))
        explicitWindow.close()
        precondition(windows.owner(of: chat, excluding: currentID) == nil)
        print("Passed: live-window focus, close with retained store, and explicit reopening.")
    }

    @MainActor private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
