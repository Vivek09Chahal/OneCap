import AppKit
import SwiftUI

/// Keep native title-bar chrome on the same surface as the navigation rail.
struct WindowFrameAppearance: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> FrameView { FrameView(color: color) }

    func updateNSView(_ view: FrameView, context: Context) {
        guard view.color != color else { return }
        view.color = color
        view.scheduleAppearance()
    }

    final class FrameView: NSView {
        var color: NSColor
        private var appearanceScheduled = false

        init(color: NSColor) {
            self.color = color
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleAppearance()
        }

        func scheduleAppearance() {
            guard !appearanceScheduled else { return }
            appearanceScheduled = true
            // Title-bar changes can force AppKit layout. Wait until the current
            // SwiftUI update or view attachment has finished before applying them.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.appearanceScheduled = false
                self.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let window, window.canBecomeKey else { return }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if window.backgroundColor != color { window.backgroundColor = color }
        }
    }
}
