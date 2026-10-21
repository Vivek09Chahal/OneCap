import DLS
import SwiftUI

struct FileChangesSummary: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let changes: FileChangeSet

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
            VStack(spacing: DLSSpacing.sm) {
                ForEach(changes.files) { file in
                    Button { store.reviewFileChanges(changes, path: file.path) } label: {
                        HStack(spacing: DLSSpacing.sm) {
                            Text(file.path).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: DLSSpacing.sm)
                            FileChangeCounts(additions: file.additions, deletions: file.deletions)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("\(file.status): \(file.path)")
                    .contextMenu {
                        OpenInEditorMenu(url: changes.folder.appendingPathComponent(file.path))
                            .disabled(!FileManager.default.fileExists(
                                atPath: changes.folder.appendingPathComponent(file.path).path))
                    }
                }
            }
            .padding(DLSSpacing.md)
        }
        .font(DLSTypography.callout)
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
                    .font(DLSTypography.captionStrong)
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
        .disabled(store.sending || store.applyingFileUndo || changes.revertedAt != nil)
        .help("Restore the files to their state before this reply")
    }

    private var reviewButton: some View {
        Button(changes.revertedAt == nil ? "View changes" : "Implement change") {
            if changes.revertedAt == nil { store.reviewFileChanges(changes) }
            else { Task { await store.restoreFileChanges(changes.id) } }
        }
        .buttonStyle(.bordered)
        .modifier(FileChangeActionHover())
        .disabled(changes.revertedAt != nil && (store.sending || store.applyingFileUndo))
    }
}
