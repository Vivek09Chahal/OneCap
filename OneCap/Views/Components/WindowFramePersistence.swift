import AppKit
import SwiftUI

/// Let AppKit restore and save the workspace frame across app launches.
struct WindowFramePersistence: NSViewRepresentable {
    var autosaveName = "OneCapWorkspace"
    func makeNSView(context: Context) -> PersistenceView { PersistenceView(autosaveName: autosaveName) }

    func updateNSView(_ view: PersistenceView, context: Context) {}

    final class PersistenceView: NSView {
        private weak var configuredWindow: NSWindow?
        private let autosaveName: String

        init(autosaveName: String) {
            self.autosaveName = autosaveName
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== configuredWindow else { return }
            saveFrame(nil)
            NotificationCenter.default.removeObserver(self)
            guard let window else { configuredWindow = nil; return }
            configuredWindow = window

            // Restore before enabling autosave so the initial default frame
            // cannot replace the user's saved frame. AppKit fits it to the screen.
            window.setFrameUsingName(autosaveName)
            window.setFrameAutosaveName(autosaveName)
            for notification in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                                 NSWindow.didEndLiveResizeNotification, NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(saveFrame(_:)), name: notification, object: window)
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(saveFrame(_:)), name: NSApplication.willTerminateNotification, object: nil)
        }

        @objc private func saveFrame(_ notification: Notification?) {
            guard let window = configuredWindow, !window.styleMask.contains(.fullScreen) else { return }
            window.saveFrame(usingName: autosaveName)
        }
    }
}
