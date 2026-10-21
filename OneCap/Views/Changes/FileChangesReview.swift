import DLS
import SwiftUI

struct FileChangesReview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let changes: FileChangeSet
    @State private var selectedPath: String?

    private var current: FileChangeSet {
        store.fileChanges.first(where: { $0.id == changes.id }) ?? changes
    }
    private var selected: FileEdit? {
        current.files.first(where: { $0.path == selectedPath }) ?? current.files.first
    }

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack {
                Text("File changes").font(DLSTypography.heading)
                FileChangeCounts(additions: current.additions, deletions: current.deletions)
                Spacer()
                if current.revertedAt != nil {
                    Text("Undone").foregroundStyle(theme.colors.textSecondary)
                }
                Button(current.revertedAt == nil ? "Undo changes" : "Implement change",
                    systemImage: current.revertedAt == nil ? "arrow.uturn.backward" : "arrow.uturn.forward") {
                    Task { await store.restoreFileChanges(current.id) }
                }
                .disabled(store.sending || store.applyingFileUndo)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(DLSSpacing.lg)
            Divider()
            if let error = store.fileChangeError {
                FileChangeUndoNotice(message: error).padding(DLSSpacing.md)
            }
            HSplitView {
                List(current.files, selection: $selectedPath) { file in
                    VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                        Text(file.path).font(DLSTypography.callout).lineLimit(2)
                        HStack {
                            Text(file.status).font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                            Spacer()
                            FileChangeCounts(additions: file.additions, deletions: file.deletions)
                        }
                    }
                    .padding(.vertical, DLSSpacing.xs).tag(file.path)
                }
                .listStyle(.sidebar).frame(minWidth: 120, idealWidth: 140, maxWidth: 220)
                if let selected { FileDiffView(file: selected).id(selected.path) }
            }
            if let notice = current.notice {
                Divider()
                Text(notice).font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(DLSSpacing.md)
            }
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 520, idealHeight: 680)
        .foregroundStyle(theme.colors.textPrimary).background(theme.colors.background)
        .onAppear { selectedPath = store.reviewedFilePath ?? current.files.first?.path }
    }
}

private struct FileDiffView: View {
    @Environment(\.dlsTheme) private var theme
    let file: FileEdit
    @State private var highlighted: [AttributedString] = []
    @State private var widestLine: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.none) {
            Text(file.path).font(DLSTypography.monoCaption).padding(DLSSpacing.md)
            Divider()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: DLSSpacing.none) {
                        if file.diff.isEmpty {
                            Text(file.before == nil ? "Empty file added" : "Empty file deleted")
                                .foregroundStyle(theme.colors.textSecondary).padding(DLSSpacing.md)
                        }
                        ForEach(Array(file.diff.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                            Text(highlighted.indices.contains(index) ? highlighted[index] : AttributedString(line))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                                    widestLine = max(widestLine, $0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DLSSpacing.md).padding(.vertical, DLSSpacing.xxs)
                                .background(line.hasPrefix("+") ? theme.colors.success.opacity(0.08) : line.hasPrefix("-") ? theme.colors.danger.opacity(0.08) : .clear)
                        }
                    }
                    .font(DLSTypography.monoCaption)
                    .frame(width: max(geometry.size.width, widestLine + 2 * DLSSpacing.md), alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: [file.path, file.diff, theme.rawValue]) {
            highlighted = []
            do {
                let lines = try await FileSyntaxHighlighter.shared.lines(for: file, dark: theme == .dark)
                try Task.checkCancellation()
                highlighted = lines
            } catch { /* Plain text remains available if highlighting fails or is cancelled. */ }
        }
    }
}
