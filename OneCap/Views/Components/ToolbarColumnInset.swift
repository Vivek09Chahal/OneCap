import AppKit
import SwiftUI

/// Reserve the space above the history pane while keeping toolbar items native.
/// Measure in window coordinates so traffic lights and toolbar spacing are included.
struct ToolbarColumnInset: View {
    let boundary: CGFloat
    @State private var origin: CGFloat = 120

    var body: some View {
        Color.clear
            .frame(width: max(1, boundary - origin - 8), height: 1)
            .fixedSize()
            .background(ToolbarOriginReader { position in
                if abs(origin - position) > 0.5 { origin = position }
            })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ToolbarOriginReader: NSViewRepresentable {
    let update: (CGFloat) -> Void

    func makeNSView(context: Context) -> OriginView { OriginView(update: update) }
    func updateNSView(_ view: OriginView, context: Context) {
        view.update = update
        view.reportOrigin()
    }

    final class OriginView: NSView {
        var update: (CGFloat) -> Void
        private var lastOrigin: CGFloat?

        init(update: @escaping (CGFloat) -> Void) {
            self.update = update
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reportOrigin() }
        override func layout() { super.layout(); reportOrigin() }

        func reportOrigin() {
            guard window != nil else { return }
            let origin = convert(.zero, to: nil).x
            guard lastOrigin.map({ abs($0 - origin) > 0.5 }) ?? true else { return }
            lastOrigin = origin
            DispatchQueue.main.async { [weak self] in self?.update(origin) }
        }
    }
}
