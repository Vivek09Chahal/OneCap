import AppKit
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposer<Leading: View, Trailing: View>: View {
    @Environment(\.dlsTheme) private var theme
    @State private var inputFocused = false
    @Binding var draft: String
    @State private var dropTargeted = false
    @State private var selection: TextSelection?
    @State private var matches: [FolderEntry] = []
    @State private var matchesProject: URL?
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
            ChatComposerTextInput(
                text: $draft, selection: $selection,
                font: NSFont(descriptor: NSFont.systemFont(ofSize: 16, weight: .light).fontDescriptor.withDesign(.rounded)!, size: 16)!,
                textColor: NSColor(theme.colors.textPrimary),
                placeholderColor: NSColor(theme.colors.textTertiary), tint: NSColor(theme.colors.accent),
                dropFiles: { _ = acceptDroppedFiles($0) }, pasteImage: pasteImage,
                submit: handleReturn,
                moveSelection: { moveFileSelection($0) == .handled },
                escape: {
                    guard fileQuery != nil else { return false }
                    dismissedDraft = draft
                    return true
                },
                focusChanged: { inputFocused = $0 })
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
                ProjectFileSuggestions(files: query.text.isEmpty ? [] : matches, folder: project, query: query.text, selectedIndex: $selectedFile,
                    loading: searchingFiles, error: searchError, choose: chooseFile)
                    .offset(y: -ProjectFileSuggestions.height(for: query.text.isEmpty ? 0 : matches.count) - DLSSpacing.sm)
            }
        }
        .task(id: [project?.path ?? "", fileQuery.map { "/" + $0.text } ?? ""]) {
            searchError = nil
            guard let query = fileQuery, !query.text.isEmpty, let project else {
                matches = []
                matchesProject = nil
                selectedFile = 0
                searchingFiles = false
                return
            }
            if matchesProject != project {
                matches = []
                selectedFile = 0
                matchesProject = project
            }
            // Keep the current rows and panel size until the replacement results arrive.
            searchingFiles = true
            do {
                try await Task.sleep(for: .milliseconds(150))
                let files = try await fileReader.search(query.text, in: project)
                try Task.checkCancellation()
                matches = files
                selectedFile = 0
                searchingFiles = false
            } catch {
                if !Task.isCancelled {
                    matches = []
                    selectedFile = 0
                    searchError = error.localizedDescription
                    searchingFiles = false
                }
            }
        }
    }

    private func handleReturn() {
        if fileQuery != nil {
            guard !searchingFiles else { return }
            if matches.indices.contains(selectedFile) {
                let file = matches[selectedFile]
                let original = draft
                Task { @MainActor in
                    await Task.yield()
                    if draft == original { chooseFile(file) }
                }
            }
            return
        }
        guard canSubmit else { return }
        let submittedDraft = draft
        // Finish native text-input dispatch before clearing/disabling
        // the editor or updating navigation and history state.
        Task { @MainActor in
            await Task.yield()
            guard draft == submittedDraft, canSubmit else { return }
            send()
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
        guard let query = fileQuery, let project, !importingFiles, !searchingFiles else { return }
        let original = draft
        let path = "`\(file.relativePath(in: project))` "
        let updated = draft.replacingCharacters(in: query.range, with: path)
        draft = updated
        selection = TextSelection(insertionPoint: updated.index(query.range.lowerBound, offsetBy: path.count))
        dismissedDraft = updated
        inputFocused = true
        // Folder selections reference their path without importing directory contents.
        guard !file.isDirectory else { return }
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
