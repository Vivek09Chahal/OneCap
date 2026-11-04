import AppKit
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposer<Leading: View, Trailing: View>: View {
    @Environment(\.chatAppearance) private var chatAppearance
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @State private var inputFocused = false
    @Binding var draft: String
    @State private var dropTargeted = false
    @State private var selection: TextSelection?
    @State private var matches: [FolderEntry] = []
    @State private var matchesProject: URL?
    @State private var selectedFile = 0
    @State private var selectedCommand = 0
    @State private var slashError: String?
    @State private var searchingFiles = false
    @State private var searchError: String?
    @State private var dismissedDraft: String?
    @State private var dismissedSlashPrefix: String?
    @State private var fileReader = FolderDirectoryReader()
    let sending: Bool
    let stopping: Bool
    let canSend: Bool
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
                font: chatAppearance.profile.nsFont(size: chatAppearance.textSize + 2, content: true),
                textColor: NSColor(theme.colors.textPrimary),
                placeholderColor: NSColor(theme.colors.textTertiary), tint: NSColor(theme.colors.accent),
                dropFiles: { _ = acceptDroppedFiles($0) }, pasteImage: pasteImage,
                submit: handleReturn,
                moveSelection: moveSuggestionSelection,
                escape: {
                    guard fileQuery != nil || slashQuery != nil else { return false }
                    if let query = slashQuery { dismissedSlashPrefix = query.occurrencePrefix(in: draft) }
                    dismissedDraft = draft
                    return true
                },
                focusChanged: { inputFocused = $0 },
                complete: completeSuggestion)
                .help("Return to send · Shift-Return for a new line")
                .padding(.horizontal, DLSSpacing.sm)
                .padding(.top, DLSSpacing.xs)
            if draft.count >= 500 {
                Text("\(draft.count.formatted()) characters")
                    .dlsFont(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            ChatComposerControls(
                sending: sending, stopping: stopping, canSubmit: canSubmit,
                importingFiles: importingFiles, send: handleReturn, stop: stop,
                leading: leading, trailing: trailing)
        }
        .padding(DLSSpacing.md)
        .background(theme.colors.composer.opacity(0.5), in: RoundedRectangle(cornerRadius: DLSRadius.extraLarge))
        .contentShape(RoundedRectangle(cornerRadius: DLSRadius.extraLarge))
        .onDrop(of: [UTType.fileURL, .image, .pdf], isTargeted: $dropTargeted) { providers in
            guard !importingFiles else { return false }
            let conversation = store.conversationID
            Task { @MainActor in
                let urls = await ComposerDroppedFiles.load(providers)
                guard store.conversationID == conversation else { return }
                if !urls.isEmpty { _ = acceptDroppedFiles(urls) }
                else { NSSound.beep() }
            }
            return !providers.isEmpty
        }
        .overlay {
            RoundedRectangle(cornerRadius: DLSRadius.extraLarge)
                .stroke((inputFocused || dropTargeted) ? theme.colors.accent.opacity(0.6) : theme.colors.borderStrong.opacity(0.65), lineWidth: DLSSize.border)
        }
        .animation(.easeOut(duration: 0.15), value: inputFocused)
        .overlay(alignment: .topLeading) {
            if slashQuery != nil {
                ComposerSlashSuggestions(rows: slashRows, selectedIndex: $selectedCommand,
                    emptyMessage: slashEmptyMessage, choose: chooseCommand)
                    .offset(y: -ComposerSlashSuggestions.height(for: slashRows.count) - DLSSpacing.sm)
            } else if let query = fileQuery, let project {
                ProjectFileSuggestions(files: query.text.isEmpty ? [] : matches, folder: project, query: query.text, selectedIndex: $selectedFile,
                    loading: searchingFiles, error: searchError, choose: chooseFile)
                    .offset(y: -ProjectFileSuggestions.height(for: query.text.isEmpty ? 0 : matches.count) - DLSSpacing.sm)
            }
        }
        .onChange(of: slashQuery) { selectedCommand = 0 }
        .onChange(of: draft) {
            if let prefix = dismissedSlashPrefix, !draft.hasPrefix(prefix) { dismissedSlashPrefix = nil }
        }
        .onChange(of: store.conversationID) {
            dismissedSlashPrefix = nil
            dismissedDraft = nil
        }
        .task(id: [slashQuery?.command ?? "", project?.path ?? ""]) {
            slashError = nil
            guard slashQuery?.command == "skill" else { return }
            do { try await store.discoverSkills(project: project) }
            catch { if !Task.isCancelled { slashError = error.localizedDescription } }
        }
        .task(id: [project?.path ?? "", fileQuery.map { "@" + $0.text } ?? ""]) {
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
        if slashQuery != nil {
            _ = completeSuggestion()
            return
        }
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

    private var slashQuery: ComposerSlashQuery? {
        guard inputFocused, !importingFiles, draft != dismissedDraft else { return nil }
        let query: ComposerSlashQuery?
        if let selection {
            guard case .selection(let range) = selection.indices, range.isEmpty else { return nil }
            query = ComposerSlashQuery.active(in: draft, at: range.lowerBound)
        } else {
            query = ComposerSlashQuery.active(in: draft)
        }
        guard let query, query.occurrencePrefix(in: draft) != dismissedSlashPrefix else { return nil }
        return query
    }

    private var slashRows: [ComposerSlashSuggestion] {
        slashQuery.map { store.slashSuggestions(for: $0) } ?? []
    }

    private var slashEmptyMessage: String {
        if let slashError { return slashError }
        switch slashQuery?.command {
        case "model" where slashQuery?.argument != nil:
            return store.chatUsesAgent && !store.acp.sessionReady
                ? "Connect an agent to see its models" : "No matching models. Add provider models on the Providers page."
        case "skill" where slashQuery?.argument != nil: return "No matching skills. Add skills on the Skills page."
        default: return "No matching commands. Escape to use this as message text."
        }
    }

    private func moveSuggestionSelection(_ direction: Int) -> Bool {
        if slashQuery != nil {
            let rows = slashRows
            guard !rows.isEmpty else { return true }
            for step in 1...rows.count {
                let index = (selectedCommand + direction * step + rows.count * 2) % rows.count
                if rows[index].enabled { selectedCommand = index; break }
            }
            return true
        }
        return moveFileSelection(direction) == .handled
    }

    private func completeSuggestion() -> Bool {
        guard slashQuery != nil else { return false }
        let rows = slashRows
        guard rows.indices.contains(selectedCommand), rows[selectedCommand].enabled else { return true }
        let row = rows[selectedCommand]
        let original = draft
        Task { @MainActor in
            // Finish the native key dispatch before changing the editor or opening a panel.
            await Task.yield()
            if draft == original { chooseCommand(row) }
        }
        return true
    }

    private func chooseCommand(_ row: ComposerSlashSuggestion) {
        guard let query = slashQuery, slashRows.contains(where: { $0.id == row.id && $0.enabled }) else { return }
        let replacement: String
        if case .command(let command) = row.action { replacement = "/" + command + " " }
        else { replacement = "" }
        let insertionOffset = draft.distance(from: draft.startIndex, to: query.range.lowerBound) + replacement.count
        let updated = draft.replacingCharacters(in: query.range, with: replacement)
        draft = updated
        selection = TextSelection(insertionPoint: updated.index(updated.startIndex, offsetBy: insertionOffset))
        inputFocused = true
        let conversation = store.conversationID
        switch row.action {
        case .command: break
        case .clear: store.newChat(preservingWorkspace: true)
        case .provider(let id): store.selectProvider(id)
        case .model(let option, let value):
            Task { await store.changeSessionOption(option, value: value) }
        case .skill(let id):
            Task { await store.attachSkill(id) }
        case .files:
            Task {
                let files = await WorkspaceFolderPicker.chooseFiles()
                if store.conversationID == conversation, !files.isEmpty { await store.attachFiles(files) }
            }
        case .folder:
            Task {
                if let folder = await WorkspaceFolderPicker.choose(), store.conversationID == conversation,
                   !store.sending, !store.connecting, !store.acp.updatingConfiguration {
                    store.selectWorkspace(folder)
                }
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
        guard project != nil, slashQuery == nil, inputFocused, !importingFiles, draft != dismissedDraft else { return nil }
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
        let replacement = file.isDirectory ? "`\(file.relativePath(in: project))` " : ""
        let updated = draft.replacingCharacters(in: query.range, with: replacement)
        draft = updated
        selection = TextSelection(insertionPoint: updated.index(query.range.lowerBound, offsetBy: replacement.count))
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
        slashQuery == nil && !importingFiles && canSend
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
