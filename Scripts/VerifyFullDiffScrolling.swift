// Compile against the app's Debug module and debug dylib, as with the other UI fixtures.
import AppKit
import DLS
import SwiftUI
@testable import OneCap

@main struct VerifyFullDiffScrolling {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            // The widest line starts offscreen. Scrolling to it must not resize
            // the document or require a geometry callback from the row.
            let longLine = "+" + String(repeating: "wide text ", count: 150)
            var lines = (0..<2_000).map { "+line \($0)" }
            lines[1_800] = longLine
            let file = FileEdit(path: "large.txt", before: nil, after: nil, permissions: nil,
                additions: lines.count, deletions: 0, diff: lines.joined(separator: "\n"))
            let theme = DLSTheme.light
            let expectedWidth = (longLine as NSString).size(withAttributes: [
                .font: theme.profile.nsFont(size: theme.profile.codeSize, code: true)
            ]).width
            let host = NSHostingView(rootView: FileDiffView(file: file).environment(\.dlsTheme, theme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)

            @MainActor func findScroll(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                for child in view.subviews {
                    if let scroll = findScroll(child) { return scroll }
                }
                return nil
            }
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
                if let document = findScroll(host)?.documentView,
                   document.frame.width >= expectedWidth, document.frame.height > 20_000 { break }
            }
            guard let scroll = findScroll(host), let document = scroll.documentView else {
                fatalError("Missing full diff scroll view")
            }
            precondition(document.frame.width >= expectedWidth, "Offscreen lines must contribute to initial horizontal extent")
            precondition(document.frame.height > 20_000, "All diff rows must remain reachable")
            let width = document.frame.width
            for fraction in [0.9, 1.0, 0.4, 0.0, 0.9] {
                scroll.contentView.scroll(to: NSPoint(x: 0,
                    y: max(0, document.frame.height - scroll.contentSize.height) * fraction))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(30))
                precondition(abs(document.frame.width - width) < 1, "Scrolling must not resize diff content")
            }
            print("PASS: 2,000-line full diff retains horizontal extent across five scroll/layout passes")
            window.close()
            exit(0)
        }
        NSApp.run()
    }
}
