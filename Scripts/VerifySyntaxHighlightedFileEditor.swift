import AppKit
import Observation
import SwiftUI

@testable import OneCap

@MainActor @Observable private final class EditorFixtureState {
    var text = "import Foundation\nlet greeting = \"Hello 🌍\"\n"
    var dark = true
}

private struct EditorFixture: View {
    @Bindable var state: EditorFixtureState
    var body: some View {
        SyntaxHighlightedFileEditor(text: $state.text, path: "Example.swift", dark: state.dark,
                                    textColor: state.dark ? .white : .black)
    }
}

// Compile against the app's Debug module and debug dylib, as with the other UI scripts.
@main
struct VerifySyntaxHighlightedFileEditor {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let state = EditorFixtureState()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = NSHostingController(rootView: EditorFixture(state: state))
        try await wait(window) { findEditor(window.contentView) != nil }
        let editor = findEditor(window.contentView)!
        window.makeFirstResponder(editor)
        try await wait(window) { colors(editor).count >= 2 }
        let original = state.text
        let darkColors = colors(editor)
        let caret = NSRange(location: (original as NSString).range(of: "greeting").location, length: 0)
        editor.setSelectedRange(caret)
        state.dark = false
        try await wait(window) { colors(editor).count >= 2 && colors(editor) != darkColors }
        precondition(editor.selectedRange() == caret, "Theme changes must preserve the caret")
        precondition(editor.string == original && state.text == original)
        precondition(editor.undoManager?.canUndo != true, "Colors must not create undo entries")

        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.insertText("let count = 42\n", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        let updated = original + "let count = 42\n"
        try await wait(window) { state.text == updated && colors(editor).count >= 2 }
        let selection = editor.selectedRange()
        try await Task.sleep(for: .milliseconds(200))
        precondition(editor.selectedRange() == selection && editor.string == updated)
        precondition(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        try await wait(window) { state.text == original && editor.string == original }
        editor.undoManager?.redo()
        try await wait(window) { state.text == updated && editor.string == updated }

        // Programmatic reloads replace the draft and invalidate older coloring jobs.
        state.text = "// Reloaded\nlet flag = false\n"
        try await wait(window) { editor.string == state.text && colors(editor).count >= 2 }
        precondition(editor.undoManager?.canUndo != true)
        print("Verified live syntax colors in both themes, Unicode text, caret preservation, typing, undo/redo, and reload.")
    }

    @MainActor private static func findEditor(_ view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { findEditor($0) }.first
    }

    @MainActor private static func colors(_ editor: NSTextView) -> Set<NSColor> {
        guard let layout = editor.layoutManager else { return [] }
        return Set((0..<editor.string.utf16.count).compactMap {
            layout.temporaryAttribute(.foregroundColor, atCharacterIndex: $0, effectiveRange: nil) as? NSColor
        })
    }

    @MainActor private static func wait(_ window: NSWindow, until condition: () -> Bool) async throws {
        for _ in 0..<300 {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw AppFailure("Timed out waiting for syntax editor")
    }
}
