import AppKit
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposer<Leading: View, Trailing: View>: View {
    @Environment(\.dlsTheme) private var theme
    @FocusState private var inputFocused: Bool
    @Binding var draft: String
    @State private var dropTargeted = false
    @State private var selection: TextSelection?
    @State private var matches: [FolderEntry] = []
    @State private var selectedFile = 0
    @State private var searchingFiles = false
    @State private var searchError: String?
    @State private var dismissedDraft: String?
    @State private var fileReader = FolderDirectoryReader()
    let sending: Bool
    let stopping: Bool
    let canSend: Bool
    let status: String
    let send: () -> Void
    let stop: () -> Void
    var attachments: [ChatAttachment] = []
    var importingFiles = false
    var pasteImage: (Data) -> Void = { _ in }
    var dropFiles: ([URL]) -> Void = { _ in }
    var removeAttachment: (UUID) -> Void = { _ in }
    var project: URL?
    var selectFile: (URL) async -> Bool = { _ in false }
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            if !attachments.isEmpty {
                ChatAttachmentStrip(attachments: attachments, remove: removeAttachment)
            }
            TextField(
                "Message", text: $draft, selection: $selection,
                prompt: Text("Ask anything, or start building…").foregroundStyle(theme.colors.textTertiary),
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(DLSTypography.chatInput)
                .foregroundStyle(theme.colors.textPrimary)
                .tint(theme.colors.accent)
                .focused($inputFocused)
                .lineLimit(2...8)
                .accessibilityLabel("Message")
                .dropDestination(for: URL.self) { urls, _ in
                    acceptDroppedFiles(urls)
                } isTargeted: { dropTargeted = $0 }
                .onPasteCommand(of: [.image]) { _ in
                    if let data = NSPasteboard.general.data(forType: .png)
                        ?? NSPasteboard.general.data(forType: .tiff) { pasteImage(data) }
                }
                .onKeyPress(.return, phases: .down) { press in
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                       editor.hasMarkedText() { return .ignored }
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        // A vertical TextField can still interpret Shift-Return as submit.
                        // Insert through its native editor to preserve selection and undo.
                        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
                            return .ignored
                        }
                        editor.insertText("\n", replacementRange: editor.selectedRange())
                        return .handled
                    }
                    if fileQuery != nil {
                        if matches.indices.contains(selectedFile) {
                            let file = matches[selectedFile]
                            let original = draft
                            Task { @MainActor in
                                await Task.yield()
                                if draft == original { chooseFile(file) }
                            }
                        }
                        return .handled
                    }
                    if canSubmit {
                        let submittedDraft = draft
                        // Finish native text-input dispatch before clearing/disabling
                        // the editor or updating navigation and history state.
                        Task { @MainActor in
                            await Task.yield()
                            guard draft == submittedDraft, canSubmit else { return }
                            send()
                        }
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) { moveFileSelection(1) }
                .onKeyPress(.upArrow) { moveFileSelection(-1) }
                .onKeyPress(.escape) {
                    guard fileQuery != nil else { return .ignored }
                    dismissedDraft = draft
                    return .handled
                }
                .help("Return to send · Shift-Return for a new line")
                .padding(.horizontal, DLSSpacing.sm)
                .padding(.top, DLSSpacing.xs)
            ChatComposerControls(
                sending: sending, stopping: stopping, canSubmit: canSubmit,
                importingFiles: importingFiles, send: send, stop: stop,
                leading: leading, trailing: trailing)
        }
        .help(status)
        .padding(DLSSpacing.md)
        .contentShape(RoundedRectangle(cornerRadius: DLSRadius.extraLarge))
        .dropDestination(for: URL.self) { urls, _ in
            acceptDroppedFiles(urls)
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            RoundedRectangle(cornerRadius: DLSRadius.extraLarge)
                .stroke((inputFocused || dropTargeted) ? theme.colors.accent.opacity(0.6) : theme.colors.borderStrong.opacity(0.65), lineWidth: DLSSize.border)
        }
        .animation(.easeOut(duration: 0.15), value: inputFocused)
        .overlay(alignment: .topLeading) {
            if let query = fileQuery, let project {
                ProjectFileSuggestions(files: matches, folder: project, query: query.text, selectedIndex: $selectedFile,
                    loading: searchingFiles, error: searchError, choose: chooseFile)
                    .offset(y: -ProjectFileSuggestions.height(for: matches.count) - DLSSpacing.sm)
            }
        }
        .task(id: [project?.path ?? "", fileQuery.map { "/" + $0.text } ?? ""]) {
            matches = []
            selectedFile = 0
            searchError = nil
            guard let query = fileQuery, !query.text.isEmpty, let project else { searchingFiles = false; return }
            searchingFiles = true
            do {
                try await Task.sleep(for: .milliseconds(150))
                let files = try await fileReader.search(query.text, in: project)
                try Task.checkCancellation()
                matches = files
                searchingFiles = false
            } catch {
                if !Task.isCancelled { searchError = error.localizedDescription; searchingFiles = false }
            }
        }
    }

    private func acceptDroppedFiles(_ urls: [URL]) -> Bool {
        guard !importingFiles, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
        dropFiles(urls)
        inputFocused = true
        return true
    }

    private var fileQuery: ProjectFileQuery? {
        guard project != nil, inputFocused, !importingFiles, draft != dismissedDraft else { return nil }
        if let selection {
            guard case .selection(let range) = selection.indices, range.isEmpty else { return nil }
            return ProjectFileQuery.active(in: draft, at: range.lowerBound)
        }
        return ProjectFileQuery.active(in: draft)
    }

    private func moveFileSelection(_ direction: Int) -> KeyPress.Result {
        guard fileQuery != nil else { return .ignored }
        if !matches.isEmpty { selectedFile = (selectedFile + direction + matches.count) % matches.count }
        return .handled
    }

    private func chooseFile(_ file: FolderEntry) {
        guard let query = fileQuery, let project, !importingFiles else { return }
        let original = draft
        let path = "`\(file.relativePath(in: project))` "
        let updated = draft.replacingCharacters(in: query.range, with: path)
        draft = updated
        selection = TextSelection(insertionPoint: updated.index(query.range.lowerBound, offsetBy: path.count))
        dismissedDraft = updated
        inputFocused = true
        Task {
            if !(await selectFile(file.url)), draft == updated {
                draft = original
                selection = TextSelection(insertionPoint: original.endIndex)
            }
        }
    }
    private var canSubmit: Bool {
        !importingFiles && canSend
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

}

struct ComposerSendButton: View {
    @Environment(\.dlsTheme) private var theme
    let sending: Bool
    let stopping: Bool
    let enabled: Bool
    let send: () -> Void
    let stop: () -> Void
    
    var body: some View {
        Button(action: sending && !enabled ? stop : send) {
            Image(systemName: sending && !enabled ? "stop.fill" : "arrow.up")
                .font(DLSTypography.navigationIcon)
                .foregroundStyle(sending || enabled ? theme.colors.onAccent : theme.colors.textTertiary)
                .frame(width: ChatLayout.sendButtonSize, height: ChatLayout.sendButtonSize)
                .background(sending || enabled ? theme.colors.accent : theme.colors.border, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(sending && !enabled ? stopping : !enabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(
            sending && !enabled ? (stopping ? "Stopping response" : "Stop response") : sending ? "Queue message" : "Send message"
        )
        .help(sending && !enabled ? "Stop response" : sending ? "Queue message (Return or ⌘ Return)" : "Send message (Return or ⌘ Return)")
    }
}
