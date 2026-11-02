import AppKit
import DLS
import SwiftUI

struct FileChangesReview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let changes: FileChangeSet
    @State private var selectedPath: String?
    @State private var editing = false
    @State private var drafts: [String: ReviewedFileDraft] = [:]
    @State private var confirmingClose = false

    private var current: FileChangeSet {
        store.fileChanges.first(where: { $0.id == changes.id }) ?? changes
    }
    private var selected: FileEdit? {
        current.files.first(where: { $0.path == selectedPath }) ?? current.files.first
    }

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack {
                Text("File changes").dlsFont(.heading)
                FileChangeCounts(additions: current.additions, deletions: current.deletions)
                Spacer()
                if current.revertedAt != nil {
                    Text("Undone").foregroundStyle(theme.colors.textSecondary)
                }
                Button(current.revertedAt == nil ? "Undo changes" : "Implement change",
                    systemImage: current.revertedAt == nil ? "arrow.uturn.backward" : "arrow.uturn.forward") {
                    Task { await store.restoreFileChanges(current.id) }
                }
                .disabled(store.sending || store.applyingFileUndo || store.savingReviewedFile || drafts.values.contains(where: \.isDirty))
                Button(editing ? "View diff" : "Edit file", systemImage: editing ? "doc.text.magnifyingglass" : "pencil") {
                    editing.toggle()
                }
                .disabled(selected == nil || current.revertedAt != nil || store.applyingFileUndo || store.savingReviewedFile)
                Button("Done") {
                    if drafts.values.contains(where: \.isDirty) { confirmingClose = true }
                    else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(store.applyingFileUndo || store.savingReviewedFile)
            }
            .padding(DLSSpacing.lg)
            Divider()
            if let error = store.fileChangeError {
                FileChangeUndoNotice(message: error).padding(DLSSpacing.md)
            }
            VStack(spacing: DLSSpacing.none) {
                if current.files.count > 1 {
                    HStack {
                        Picker("File", selection: $selectedPath) {
                            ForEach(current.files) { file in
                                Text(file.path).tag(Optional(file.path))
                            }
                        }
                        .pickerStyle(.menu)
                        if let selected {
                            FileChangeCounts(additions: selected.additions, deletions: selected.deletions)
                        }
                    }
                    .padding(DLSSpacing.md)
                    Divider()
                }
                if let selected {
                    if editing {
                        ReviewedFileEditor(changes: current, file: selected, drafts: $drafts)
                            .id(selected.path)
                    } else { FileDiffView(file: selected.reviewedEdit).id(selected.path) }
                }
            }
            if let notice = current.notice {
                Divider()
                Text(notice).dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(DLSSpacing.md)
            }
        }
        .frame(minWidth: 760, idealWidth: 960, maxWidth: .infinity,
               minHeight: 520, idealHeight: 680, maxHeight: .infinity)
        .foregroundStyle(theme.colors.textPrimary).background(theme.colors.background)
        .onAppear { selectedPath = store.reviewedFilePath ?? current.files.first?.path }
        .onChange(of: current.revertedAt) { _, _ in
            editing = false
            drafts = [:]
        }
        .interactiveDismissDisabled(drafts.values.contains(where: \.isDirty) || store.applyingFileUndo || store.savingReviewedFile)
        .alert("Discard unsaved file edits?", isPresented: $confirmingClose) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard edits", role: .destructive) { dismiss() }
        } message: { Text("Saved edits are already on disk. Unsaved drafts in this review will be discarded.") }
    }
}

struct FileDiffView: View {
    @Environment(\.dlsTheme) private var theme
    let file: FileEdit
    @State private var highlighted: [AttributedString] = []
    @State private var widestLine: CGFloat = 0
    @State private var diffLines: [String] = []
    @State private var preparedKey: PreparationKey?
    @State private var highlightedKey: PreparationKey?

    private func displayLine(_ line: String, index: Int) -> AttributedString {
        var text = highlighted.indices.contains(index) ? highlighted[index] : AttributedString(line)
        if theme.preferences.diffMarkers == "Markers" { return text }
        if (line.hasPrefix("+") && !line.hasPrefix("+++")) || (line.hasPrefix("-") && !line.hasPrefix("---")) {
            if !text.characters.isEmpty { text.removeSubrange(text.startIndex..<text.characters.index(after: text.startIndex)) }
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.none) {
            Text(file.path).dlsFont(.monoCaption).padding(DLSSpacing.md)
            Divider()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: DLSSpacing.none) {
                        if file.diff.isEmpty {
                            Text(file.before == file.after ? "No remaining text changes" : file.before == nil ? "Empty file added" : "Empty file deleted")
                                .foregroundStyle(theme.colors.textSecondary).padding(DLSSpacing.md)
                        }
                        ForEach(diffLines.indices, id: \.self) { index in
                            let line = diffLines[index]
                            Text(displayLine(line, index: index))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DLSSpacing.md).padding(.vertical, DLSSpacing.xxs)
                                .background(theme.preferences.diffMarkers == "Markers" ? .clear : line.hasPrefix("+") ? theme.colors.success.opacity(0.08) : line.hasPrefix("-") ? theme.colors.danger.opacity(0.08) : .clear)
                        }
                    }
                    .font(theme.profile.font(size: theme.profile.codeSize, code: true))
                    .frame(width: max(geometry.size.width, widestLine + 2 * DLSSpacing.md), alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: PreparationKey(path: file.path, diff: file.diff, profile: theme.profile, dark: theme.colors.usesDarkSurfaces)) {
            let key = PreparationKey(path: file.path, diff: file.diff, profile: theme.profile, dark: theme.colors.usesDarkSurfaces)
            if preparedKey != key {
                let font = theme.profile.nsFont(size: theme.profile.codeSize, code: true)
                let prepared = await Self.prepare(file.diff, font: font)
                guard !Task.isCancelled else { return }
                diffLines = prepared.lines
                widestLine = prepared.width
                preparedKey = key
                highlighted = []
                highlightedKey = nil
            }
            guard highlightedKey != key else { return }
            do {
                let lines = try await FileSyntaxHighlighter.shared.lines(for: file, dark: theme.colors.usesDarkSurfaces)
                try Task.checkCancellation()
                highlighted = lines
                highlightedKey = key
            } catch { /* Plain text remains available if highlighting fails or is cancelled. */ }
        }
    }

    private struct PreparationKey: Equatable {
        let path: String
        let diff: String
        let profile: DLSVisualProfile
        let dark: Bool
    }

    @concurrent private static func prepare(_ diff: String, font: NSFont) async -> (lines: [String], width: CGFloat) {
        // Discover horizontal extent once, including offscreen lines. Publishing
        // widths from visible rows otherwise resizes the document during a scroll.
        let lines = diff.components(separatedBy: "\n")
        let width = lines.reduce(CGFloat(0)) { max($0, ($1 as NSString).size(withAttributes: [.font: font]).width) }
        return (lines, ceil(width))
    }
}
