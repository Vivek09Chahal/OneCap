import AppKit
import SwiftUI

/// Tracks native window closure independently of retained background chat stores.
struct ChatWindowAttachment: NSViewRepresentable {
    let windows: ChatWindows
    let id: UUID

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(windows: windows, id: id)
    }

    func updateNSView(_ view: AttachmentView, context: Context) {}

    final class AttachmentView: NSView {
        let windows: ChatWindows
        let id: UUID

        init(windows: ChatWindows, id: UUID) {
            self.windows = windows
            self.id = id
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            guard let window else { return }
            windows.attach(window, to: id)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            windows.closed(window, id: id)
        }
    }
}
