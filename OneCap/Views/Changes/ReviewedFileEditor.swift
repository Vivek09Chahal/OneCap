import AppKit
import DLS
import SwiftUI

/// Drafts live in the review, so switching files never throws away an unfinished edit.
struct ReviewedFileEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let changes: FileChangeSet
    let file: FileEdit
    @Binding var drafts: [String: ReviewedFileDraft]
    @State private var error: String?
    @State private var loading = false
    @State private var saving = false
    @State private var confirmingReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            HStack {
                Text(file.path).dlsFont(.monoCaption).lineLimit(1).truncationMode(.middle)
                Spacer()
                if drafts[file.path]?.isDirty == true {
                    Text("Unsaved").dlsFont(.caption).foregroundStyle(theme.colors.warning)
                }
                Button("Reload") {
                    if drafts[file.path]?.isDirty == true { confirmingReload = true }
                    else { load(force: true) }
                }.disabled(loading || saving)
                    .help("Reload the file from disk and discard this file’s draft")
                Button(saving ? "Saving…" : "Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(loading || saving || drafts[file.path] == nil || store.sending || store.applyingFileUndo || store.savingReviewedFile)
            }
            .padding(DLSSpacing.md)
            Divider()
            if let error {
                Text(error).dlsFont(.callout).foregroundStyle(theme.colors.danger).padding(.horizontal, DLSSpacing.md)
            }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if drafts[file.path] != nil {
                SyntaxHighlightedFileEditor(text: Binding(
                    get: { drafts[file.path]?.text ?? "" },
                    set: { drafts[file.path]?.text = $0 }),
                    path: file.path, dark: theme.isDark, textColor: NSColor(theme.colors.textPrimary))
                    .padding(.horizontal, DLSSpacing.sm)
                    .accessibilityLabel("Edit \(file.path)")
            } else { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { load() }
        .alert("Discard this file’s unsaved edits?", isPresented: $confirmingReload) {
            Button("Keep editing", role: .cancel) {}
            Button("Reload file", role: .destructive) { load(force: true) }
        } message: { Text("The latest version on disk will replace this file’s draft.") }
    }

    private func load(force: Bool = false) {
        guard force || drafts[file.path] == nil else { return }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                let text = try await store.fileChangeTracker.editableText(path: file.path, folder: changes.folder)
                drafts[file.path] = ReviewedFileDraft(text: text ?? "", savedText: text)
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        guard let draft = drafts[file.path] else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await store.saveReviewedFile(draft.text, path: file.path, changesID: changes.id, expected: draft.savedText)
                drafts[file.path]?.savedText = draft.text
            } catch { self.error = error.localizedDescription }
        }
    }
}
