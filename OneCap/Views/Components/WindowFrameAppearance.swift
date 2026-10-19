import AppKit
import SwiftUI

/// Keep native title-bar chrome on the same surface as the navigation rail.
struct WindowFrameAppearance: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> FrameView { FrameView(color: color) }

    func updateNSView(_ view: FrameView, context: Context) {
        view.color = color
        view.applyAppearance()
    }

    final class FrameView: NSView {
        var color: NSColor

        init(color: NSColor) {
            self.color = color
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = color
        }
    }
}
