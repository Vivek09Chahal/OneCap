import DLS
import SwiftUI

struct FileChangesSummary: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @State private var isExpanded = false
    @State private var reviewingInline = false
    let changes: FileChangeSet

    init(changes: FileChangeSet) {
        self.changes = changes
    }

    private var visibleFiles: [FileEdit] {
        isExpanded ? changes.files : Array(changes.files.prefix(4))
    }

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DLSSpacing.md) {
                    heading.fixedSize()
                    Spacer(minLength: DLSSpacing.sm)
                    actions.fixedSize()
                }
                VStack(alignment: .leading, spacing: DLSSpacing.md) {
                    heading
                    HStack { Spacer(); actions }
                }
            }
            .padding(DLSSpacing.md)
            Divider()
            if let error = store.fileChangeError {
                FileChangeUndoNotice(message: error).padding(DLSSpacing.md)
            }
            LazyVStack(spacing: DLSSpacing.sm) {
                ForEach(visibleFiles) { file in
                    InlineFileReview(changes: changes, file: file, expandAll: reviewingInline)
                }
                if changes.files.count > 4 {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DLSSpacing.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.textSecondary)
                    .help(isExpanded ? "Show fewer files" : "Show all \(changes.files.count) files")
                    .accessibilityLabel(isExpanded ? "Show fewer files" : "Show all \(changes.files.count) files")
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                }
            }
            .padding(DLSSpacing.md)
        }
        .dlsFont(.callout)
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: DLSRadius.medium).stroke(theme.colors.border))
    }

    private var heading: some View {
        HStack(spacing: DLSSpacing.md) {
            Image(systemName: "doc.badge.plus")
                .font(DLSTypography.navigationIcon)
                .padding(DLSSpacing.md)
                .background(theme.colors.background, in: RoundedRectangle(cornerRadius: DLSRadius.small))
            VStack(alignment: .leading, spacing: DLSSpacing.xxs) {
                Text(changes.revertedAt == nil ? "Edited \(changes.files.count) \(changes.files.count == 1 ? "file" : "files")" : "Changes undone")
                    .dlsFont(.captionStrong)
                FileChangeCounts(additions: changes.additions, deletions: changes.deletions)
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DLSSpacing.md) {
                undoButton
                OpenInEditorMenu(url: changes.folder)
                reviewButton
            }
            .fixedSize()
            VStack(alignment: .trailing, spacing: DLSSpacing.sm) {
                OpenInEditorMenu(url: changes.folder)
                HStack(spacing: DLSSpacing.md) {
                    undoButton
                    reviewButton
                }
            }
        }
    }

    private var undoButton: some View {
        Button {
            Task { await store.restoreFileChanges(changes.id) }
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .padding(.horizontal, DLSSpacing.sm)
                .padding(.vertical, DLSSpacing.xs)
                .contentShape(RoundedRectangle(cornerRadius: DLSRadius.small))
        }
        .buttonStyle(.plain)
        .modifier(FileChangeActionHover())
        .disabled(store.sending || store.applyingFileUndo || store.savingReviewedFile || changes.revertedAt != nil)
        .help("Restore the files to their state before this reply")
    }

    private var reviewButton: some View {
        Button(changes.revertedAt == nil ? (reviewingInline ? "Hide changes" : "View changes") : "Implement change") {
            if changes.revertedAt == nil {
                reviewingInline.toggle()
                if reviewingInline { isExpanded = true }
            } else { Task { await store.restoreFileChanges(changes.id) } }
        }
        .buttonStyle(.bordered)
        .modifier(FileChangeActionHover())
        .disabled(store.sending || store.applyingFileUndo || store.savingReviewedFile)
    }
}
