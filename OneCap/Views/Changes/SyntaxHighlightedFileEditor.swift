import AppKit
import SwiftUI

/// Syntax colors are temporary layout attributes, so recoloring never changes
/// the draft, selection, typing attributes, or the editor's undo history.
struct SyntaxHighlightedFileEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let path: String
    let dark: Bool
    let textColor: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = NSTextView(usingTextLayoutManager: false)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.delegate = context.coordinator
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        coordinator.isUpdatingView = true
        defer { coordinator.isUpdatingView = false }
        if editor.isEditable != isEnabled { editor.isEditable = isEnabled }
        if editor.textColor != textColor { editor.textColor = textColor }
        if editor.insertionPointColor != textColor { editor.insertionPointColor = textColor }
        let label = "Edit \(path)"
        if editor.accessibilityLabel() != label { editor.setAccessibilityLabel(label) }
        // Do not overwrite keystrokes awaiting publication with the older binding.
        if let pending = coordinator.pendingEdit, text == pending.baseline { return }
        coordinator.pendingEdit = nil
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
            coordinator.highlightRequest = nil
        }
        coordinator.highlight(editor)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.isActive = false
        coordinator.pendingEdit = nil
        coordinator.highlightTask?.cancel()
        (scroll.documentView as? NSTextView)?.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedFileEditor
        var isUpdatingView = false
        var isActive = true
        var pendingEdit: (text: String, baseline: String)?
        var highlightTask: Task<Void, Never>?
        var highlightRequest: HighlightRequest?
        private var editScheduled = false

        struct HighlightRequest: Equatable {
            let source: String
            let path: String
            let dark: Bool
        }

        init(_ parent: SyntaxHighlightedFileEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard isActive, !isUpdatingView, let editor = notification.object as? NSTextView else { return }
            pendingEdit = (editor.string, pendingEdit?.baseline ?? parent.text)
            highlight(editor)
            guard !editScheduled else { return }
            editScheduled = true
            // Native layout callbacks must not modify SwiftUI state synchronously.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.editScheduled = false
                guard self.isActive, let edit = self.pendingEdit else { return }
                self.pendingEdit = nil
                guard self.parent.text == edit.baseline else { return }
                if self.parent.text != edit.text { self.parent.text = edit.text }
            }
        }

        func highlight(_ editor: NSTextView) {
            let request = HighlightRequest(source: editor.string, path: parent.path, dark: parent.dark)
            guard request != highlightRequest else { return }
            highlightRequest = request
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self, weak editor] in
                do {
                    // Coalesce typing before highlighting a complete multiline snapshot.
                    try await Task.sleep(for: .milliseconds(100))
                    let colored = try await FileSyntaxHighlighter.shared.code(
                        request.source, path: request.path, dark: request.dark)
                    try Task.checkCancellation()
                    guard let self, self.isActive, self.highlightRequest == request,
                          let editor, editor.string == request.source,
                          let layout = editor.layoutManager else { return }
                    let attributed = NSAttributedString(colored)
                    guard attributed.string == editor.string else { return }
                    let fullRange = NSRange(location: 0, length: attributed.length)
                    layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
                    attributed.enumerateAttribute(.foregroundColor, in: fullRange) { color, range, _ in
                        if let color {
                            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
                        }
                    }
                    editor.needsDisplay = true
                } catch { /* Keep the editable plain text if highlighting fails or is cancelled. */ }
            }
        }
    }
}
