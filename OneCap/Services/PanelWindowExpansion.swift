import AppKit

@MainActor final class PanelWindowExpansion {
    static let minimumWidthWithPanel: CGFloat = 1600
    weak var window: NSWindow?

    func ensureMinimumWidth() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let screen = window.screen else { return }
        let frame = Self.expandedFrame(
            window.frame, minimumWidth: Self.minimumWidthWithPanel,
            within: screen.visibleFrame, maximumWidth: window.maxSize.width)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    /// Grow to the right when possible, shifting left only to stay on the same screen.
    /// Reopening the panel at or above the minimum never grows the window again.
    static func expandedFrame(
        _ frame: NSRect, minimumWidth: CGFloat, within screen: NSRect,
        maximumWidth: CGFloat = .greatestFiniteMagnitude
    ) -> NSRect {
        guard minimumWidth.isFinite, minimumWidth > frame.width else { return frame }
        let available = max(0, min(screen.width, maximumWidth) - frame.width)
        let growth = min(minimumWidth - frame.width, available)
        guard growth > 0 else { return frame }
        var result = frame
        result.size.width += growth
        result.origin.x = max(screen.minX, min(frame.minX, screen.maxX - result.width))
        return result
    }
}
