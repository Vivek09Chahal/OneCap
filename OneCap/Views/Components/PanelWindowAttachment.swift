import AppKit
import SwiftUI

/// Capture this chat's own window rather than relying on whichever window is key.
struct PanelWindowAttachment: NSViewRepresentable {
    let expansion: PanelWindowExpansion

    func makeNSView(context: Context) -> AttachmentView { AttachmentView(expansion: expansion) }

    func updateNSView(_ view: AttachmentView, context: Context) {
        if expansion.window !== view.window { expansion.window = view.window }
    }

    final class AttachmentView: NSView {
        let expansion: PanelWindowExpansion

        init(expansion: PanelWindowExpansion) {
            self.expansion = expansion
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            expansion.window = window
        }
    }
}
