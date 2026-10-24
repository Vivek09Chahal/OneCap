import AppKit
import SwiftUI

/// Handles file and image drops before AppKit can insert their paths into the draft.
struct ChatComposerTextInput: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    @Binding var selection: TextSelection?
    let font: NSFont
    let textColor: NSColor
    let placeholderColor: NSColor
    let tint: NSColor
    let dropFiles: ([URL]) -> Void
    let pasteImage: (Data) -> Void
    let submit: () -> Void
    let moveSelection: (Int) -> Bool
    let escape: () -> Bool
    let focusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ComposerTextView()
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Message")
        editor.registerForDraggedTypes([.fileURL, .png, .tiff]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        // AppKit sends delegate notifications synchronously while applying SwiftUI state.
        context.coordinator.isUpdatingView = true
        defer { context.coordinator.isUpdatingView = false }
        editor.owner = context.coordinator
        if editor.isEditable != isEnabled { editor.isEditable = isEnabled }
        if editor.font != font { editor.font = font }
        if editor.textColor != textColor { editor.textColor = textColor }
        if editor.placeholderColor != placeholderColor {
            editor.placeholderColor = placeholderColor
            editor.needsDisplay = true
        }
        if editor.insertionPointColor != tint { editor.insertionPointColor = tint }
        // A layout pass may run before queued native edits reach the bindings.
        // Keep those edits in the editor unless SwiftUI supplied newer state.
        guard context.coordinator.shouldApplyBoundState else { return }
        if editor.string != text {
            editor.string = text
            editor.needsDisplay = true
        }
        if let selection, case .selection(let range) = selection.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let selected = NSRange(range, in: text)
            if editor.selectedRange() != selected { editor.setSelectedRange(selected) }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.isActive = false
        coordinator.pendingUpdate = nil
        (scroll.documentView as? ComposerTextView)?.owner = nil
        (scroll.documentView as? NSTextView)?.delegate = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let bounds = (text.isEmpty ? " " : text + "\n").boundingRect(
            with: NSSize(width: max(1, width - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return CGSize(width: width, height: min(lineHeight * 8, max(lineHeight * 2, ceil(bounds.height))))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerTextInput
        var isUpdatingView = false
        fileprivate var isActive = true
        fileprivate var pendingUpdate: EditorUpdate?
        private var updateScheduled = false

        fileprivate struct EditorUpdate {
            var text: String
            var selection: NSRange
            let baseText: String
            let baseSelection: TextSelection?
        }

        var shouldApplyBoundState: Bool {
            guard let pendingUpdate else { return true }
            if parent.text == pendingUpdate.baseText, parent.selection == pendingUpdate.baseSelection {
                return false
            }
            // Sending, switching chats, or choosing a file supersedes queued edits.
            self.pendingUpdate = nil
            return true
        }

        init(_ parent: ChatComposerTextInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !isUpdatingView, let editor = notification.object as? NSTextView else { return }
            scheduleUpdate(from: editor)
            editor.needsDisplay = true
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingView, let editor = notification.object as? NSTextView else { return }
            scheduleUpdate(from: editor)
        }
        func focusChanged(_ focused: Bool) {
            // First-responder changes can also occur during a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.parent.focusChanged(focused)
            }
        }
        private func scheduleUpdate(from editor: NSTextView) {
            guard isActive else { return }
            pendingUpdate = EditorUpdate(
                text: editor.string, selection: editor.selectedRange(),
                baseText: pendingUpdate?.baseText ?? parent.text,
                baseSelection: pendingUpdate.map { $0.baseSelection } ?? parent.selection)
            guard !updateScheduled else { return }
            updateScheduled = true
            // AppKit can notify during layout, outside updateNSView's guard.
            // Publish text and its matching selection after SwiftUI finishes updating.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard self.isActive, let update = self.pendingUpdate else { return }
                self.pendingUpdate = nil
                guard self.parent.text == update.baseText,
                      self.parent.selection == update.baseSelection else { return }
                if self.parent.text != update.text { self.parent.text = update.text }
                guard let range = Range(update.selection, in: update.text) else { return }
                if let selection = self.parent.selection, case .selection(let current) = selection.indices,
                   current == range { return }
                self.parent.selection = TextSelection(range: range)
            }
        }
    }
}

private final class ComposerTextView: NSTextView {
    weak var owner: ChatComposerTextInput.Coordinator?
    var placeholderColor = NSColor.placeholderTextColor
    private let filePromiseQueue = OperationQueue()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Ask anything, or start building…" as NSString).draw(
                in: bounds, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: placeholderColor])
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { owner?.focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { owner?.focusChanged(false) }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        guard isEditable, !hasMarkedText(), let parent = owner?.parent else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 36, 76:
            if event.modifierFlags.intersection([.shift, .option]).isEmpty { parent.submit(); return }
            // A vertical TextField can still interpret Shift-Return as submit.
            // Insert through its native editor to preserve selection and undo.
            insertNewline(nil)
            return
        case 125: if parent.moveSelection(1) { return }
        case 126: if parent.moveSelection(-1) { return }
        case 53: if parent.escape() { return }
        default: break
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if acceptAttachments(from: .general) { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable else { return [] }
        return canAttach(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable else { return [] }
        return canAttach(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        if acceptAttachments(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        return canAttach(sender.draggingPasteboard) || super.prepareForDragOperation(sender)
    }

    private func canAttach(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    private func acceptAttachments(from pasteboard: NSPasteboard) -> Bool {
        guard let parent = owner?.parent else { return false }
        // Screenshot thumbnails and other unsaved drags provide a file promise,
        // which must be fulfilled before the attachment importer can read it.
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("OneCap-Drops", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                NSSound.beep()
                return false
            }
            for promise in promises {
                promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: filePromiseQueue) { [weak self] url, error in
                    let succeeded = error == nil
                    Task { @MainActor [weak self] in
                        guard let self, let owner = self.owner, owner.isActive else { return }
                        guard succeeded else { NSSound.beep(); return }
                        owner.parent.dropFiles([url])
                    }
                }
            }
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            parent.dropFiles(urls)
            return true
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            parent.pasteImage(data)
            return true
        }
        return false
    }
}
