// Compile against the app's Debug module and debug dylib, as with other UI fixtures.
import AppKit
import DLS
import SwiftUI
@testable import OneCap

@main struct VerifyInlineHunkReview {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-hunk-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        let before = "struct Greeting {\n    let title = \"Hello\"\n    let subtitle = \"Welcome\"\n}\n"
        let after = "struct Greeting {\n    let title = \"Hello, world\"\n    let subtitle = \"Welcome\"\n}\n"
        let diff = FileTextDiff.make(before: before, after: after)
        let file = FileEdit(path: "Sources/Greeting.swift", before: before, after: after, permissions: nil,
            additions: diff.added, deletions: diff.removed, diff: diff.text)
        let changes = FileChangeSet(replyID: UUID(), folder: root, createdAt: .now, files: [file])
        store.fileChanges = [changes]
        for width in [760, 400] {
            let host = NSHostingView(rootView:
                FileChangesSummary(changes: changes).environment(store).padding(20).frame(width: CGFloat(width)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/OneCap-hunk-preview-\(width).png"))
            window.orderOut(nil)
        }
        print("PASS: Inline file review rendered at 760 and 400 points")
    }
}
