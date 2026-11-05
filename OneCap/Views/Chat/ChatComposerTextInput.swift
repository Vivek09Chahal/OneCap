import DLS
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    var complete: () -> Bool = { false }

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
            + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        NavigationTrace.mark("composer update BEGIN")
        defer { NavigationTrace.mark("composer update END") }
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
        NavigationTrace.mark("composer dismantle BEGIN")
        defer { NavigationTrace.mark("composer dismantle END") }
        // Invalidate callbacks before resigning: AppKit can synchronously notify
        // delegates during the focus handoff while SwiftUI is dismantling us.
        coordinator.isActive = false
        coordinator.highlightTask?.cancel()
        coordinator.pendingUpdate = nil
        coordinator.pendingFilePromises.removeAll()
        (scroll.documentView as? ComposerTextView)?.owner = nil
        (scroll.documentView as? NSTextView)?.delegate = nil
        if let editor = scroll.documentView as? NSTextView,
           let window = editor.window, window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
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
        fileprivate var pendingFilePromises: [UUID: NSFilePromiseReceiver] = [:]
        var highlightTask: Task<Void, Never>?

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

        func filePromiseCompletion(id: UUID? = nil) -> @Sendable (URL, Error?) -> Void {
            // AppKit invokes this on the file-promise operation queue. A Sendable
            // callback must hop to the main actor before touching the editor.
            return { @Sendable [weak self] url, error in
                let succeeded = error == nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let id { self.pendingFilePromises[id] = nil }
                    guard self.isActive else { return }
                    guard succeeded else { NSSound.beep(); return }
                    self.parent.dropFiles([url])
                }
            }
        }

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
            NavigationTrace.mark("composer focus callback scheduled; focused=\(focused)")
            // First-responder changes can also occur during a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in
                NavigationTrace.mark("composer queued focus callback; active=\(self?.isActive == true)")
                guard let self, self.isActive else { return }
                NavigationTrace.mark("composer BEFORE focus binding callback")
                self.parent.focusChanged(focused)
                NavigationTrace.mark("composer AFTER focus binding callback")
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
                NavigationTrace.mark("composer queued text callback; active=\(self?.isActive == true)")
                guard let self else { return }
                self.updateScheduled = false
                guard self.isActive, let update = self.pendingUpdate else { return }
                self.pendingUpdate = nil
                guard self.parent.text == update.baseText,
                      self.parent.selection == update.baseSelection else { return }
                NavigationTrace.mark("composer BEFORE text/selection binding writes")
                defer { NavigationTrace.mark("composer AFTER text/selection binding writes") }
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
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let smooth = DLSVisualPreferences.saved.fontSmoothing
        NSGraphicsContext.current?.shouldAntialias = smooth
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(smooth)
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Ask anything · / for commands · @ for files" as NSString).draw(
                in: bounds, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: placeholderColor])
        }
    }

    override func becomeFirstResponder() -> Bool {
        NavigationTrace.mark("composer becomeFirstResponder BEGIN")
        defer { NavigationTrace.mark("composer becomeFirstResponder END") }
        let accepted = super.becomeFirstResponder()
        if accepted { owner?.focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        NavigationTrace.mark("composer resignFirstResponder BEGIN")
        defer { NavigationTrace.mark("composer resignFirstResponder END") }
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
        case 48:
            if event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
               parent.complete() { return }
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
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func acceptAttachments(from pasteboard: NSPasteboard) -> Bool {
        guard let owner else { return false }
        let parent = owner.parent
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
                let id = UUID()
                owner.pendingFilePromises[id] = promise
                promise.receivePromisedFiles(
                    atDestination: destination, options: [:], operationQueue: filePromiseQueue,
                    reader: owner.filePromiseCompletion(id: id))
            }
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            parent.dropFiles(urls)
            return true
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            ?? (NSImage(pasteboard: pasteboard)?.tiffRepresentation) {
            parent.pasteImage(data)
            return true
        }
        return false
    }
}

/// SwiftUI's composer surface must accept promised representations, not only existing URLs.
@MainActor
enum ComposerDroppedFiles {
    static func load(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            // Unsaved screenshot thumbnails vend image data before a file exists.
            let representation = provider.registeredTypeIdentifiers.first {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .image) || type.conforms(to: .pdf)
            }
            if let representation, let url = await materialize(provider, type: representation) {
                urls.append(url)
            } else if let data = await data(provider, type: UTType.fileURL.identifier),
                      let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }

    private static func materialize(_ provider: NSItemProvider, type: String) async -> URL? {
        let suggestedName = provider.suggestedName
        // Copy inside the completion: provider-owned temporary files expire when it returns.
        let file: URL? = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                continuation.resume(returning: url.flatMap { persist($0, name: suggestedName) })
            }
        }
        if let file { return file }
        guard let bytes = await data(provider, type: type) else { return nil }
        let suffix = UTType(type)?.preferredFilenameExtension ?? "dat"
        let name = suggestedName.map { ($0 as NSString).lastPathComponent } ?? "Dropped file.\(suffix)"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCap-Drops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var url = destination.appendingPathComponent(name)
            if url.pathExtension.isEmpty { url.appendPathExtension(suffix) }
            try bytes.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    nonisolated private static func persist(_ source: URL, name: String?) -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCap-Drops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var url = destination.appendingPathComponent((name as NSString?)?.lastPathComponent ?? source.lastPathComponent)
            if url.pathExtension.isEmpty, !source.pathExtension.isEmpty {
                url.appendPathExtension(source.pathExtension)
            }
            try FileManager.default.copyItem(at: source, to: url)
            return url
        } catch { return nil }
    }

    private static func data(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { bytes, _ in
                continuation.resume(returning: bytes)
            }
        }
    }
}

/// Debug-only checkpoints; never include the user's text or other field contents.
@MainActor enum NavigationTrace {
    private static var sequence = 0

    static func mark(_ message: String) {
        #if DEBUG
        sequence += 1
        NSLog("[NavigationTrace #%d] %@", sequence, message)
        #endif
    }
}
