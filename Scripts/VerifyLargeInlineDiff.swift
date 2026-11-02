import AppKit
import DLS
import SwiftUI
@testable import OneCap

@main struct VerifyLargeInlineDiff {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let text = (0..<10_000).map { "let value\($0) = \($0) // large diff\n" }.joined()
            let file = FileEdit(path: "Large.swift", before: nil, after: text, permissions: nil,
                additions: 10_000, deletions: 0, diff: "")
            let changes = FileChangeSet(replyID: UUID(), folder: URL(fileURLWithPath: "/tmp"), createdAt: .now, files: [file])
            let store = AppStore(stateURL: URL(fileURLWithPath: "/tmp/OneCap-scroll-probe-\(UUID()).json"))
            let host = NSHostingView(rootView: InlineFileReview(changes: changes, file: file, initiallyExpanded: true)
                .environment(store).environment(\.dlsTheme, DLSTheme.light).padding(16))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            for _ in 0..<80 {
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(25))
                if !scrollViews(host).isEmpty { break }
            }
            guard let scroll = scrollViews(host).first, let document = scroll.documentView else {
                fatalError("Large diff did not render")
            }
            precondition(document.frame.height > 100_000, "All diff lines must remain reachable")
            precondition(document.frame.width >= scroll.contentSize.width, "Diff must retain horizontal extent")
            let start = ContinuousClock.now
            for fraction in [0.1, 0.4, 0.8, 1.0, 0.0] {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentSize.height) * fraction))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(30))
            }
            print("PASS: 10,000-line inline diff renders and scrolls through all rows; five scroll/layout passes: \(start.duration(to: .now))")
            window.close()
            exit(0)
        }
        NSApp.run()
    }
}
