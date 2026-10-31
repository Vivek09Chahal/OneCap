import DLS
import SwiftUI

/// Review lives in the transcript; the separate file editor remains available for full-file work.
struct InlineFileReview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let changes: FileChangeSet
    let file: FileEdit
    @State private var expanded = false
    @State private var selectedHunkID = 0
    let expandAll: Bool

    init(changes: FileChangeSet, file: FileEdit, initiallyExpanded: Bool = false, expandAll: Bool = false) {
        self.changes = changes
        self.file = file
        self.expandAll = expandAll
        _expanded = State(initialValue: initiallyExpanded || expandAll)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            HStack(spacing: DLSSpacing.sm) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: DLSSpacing.sm) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .accessibilityHidden(true)
                        Text(file.path).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: DLSSpacing.sm)
                        FileChangeCounts(additions: file.additions, deletions: file.deletions)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Review changes in \(file.path)")
                .accessibilityLabel("Review \(file.path)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Button { store.reviewFileChanges(changes, path: file.path) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Open full file review")
                .accessibilityLabel("Open full review for \(file.path)")
            }
            .contextMenu {
                OpenInEditorMenu(url: changes.folder.appendingPathComponent(file.path))
                    .disabled(!FileManager.default.fileExists(atPath: changes.folder.appendingPathComponent(file.path).path))
            }
            if expanded {
                let hunks = file.hunks
                if let selected = hunks.first(where: { $0.id == selectedHunkID }) ?? hunks.first {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            reviewRangePicker(hunks)
                            Spacer()
                            InlineHunkActions(changesID: changes.id, file: file, hunk: selected,
                                undone: changes.revertedAt != nil)
                        }
                        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                            reviewRangePicker(hunks)
                            InlineHunkActions(changesID: changes.id, file: file, hunk: selected,
                                undone: changes.revertedAt != nil)
                        }
                    }
                    .padding(DLSSpacing.sm)
                }
                // All changed ranges share one diff surface and one scroll position.
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: DLSSpacing.none) {
                            ForEach(hunks) { hunk in
                                InlineHunkReview(changesID: changes.id, file: file, hunk: hunk,
                                    undone: changes.revertedAt != nil, reviewWidth: geometry.size.width)
                            }
                        }
                        // Include every hunk's natural width in the scrollable content size.
                        // A lazy stack can otherwise report only the viewport width while text overflows it.
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                    }
                }
                .frame(height: min(420, CGFloat(hunks.reduce(0) {
                    $0 + $1.oldLines.count + $1.newLines.count
                        + $1.leadingContext.count + $1.trailingContext.count
                }) * 24 + CGFloat(hunks.count) * 52))
                .scrollIndicators(.visible)
                .background(theme.colors.background, in: RoundedRectangle(cornerRadius: DLSRadius.small))
                .overlay(RoundedRectangle(cornerRadius: DLSRadius.small).stroke(theme.colors.border))
                if hunks.isEmpty {
                    Text("No text changes").foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .onChange(of: expandAll) { _, value in expanded = value }
    }

    private func reviewRangePicker(_ hunks: [FileDiffHunk]) -> some View {
        Picker("Review range", selection: $selectedHunkID) {
            ForEach(hunks) { hunk in
                Text("Lines \(hunk.newRange.lowerBound + 1)–\(max(hunk.newRange.lowerBound + 1, hunk.newRange.upperBound))")
                    .tag(hunk.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Review range")
    }
}

struct InlineHunkReview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let changesID: UUID
    let file: FileEdit
    let hunk: FileDiffHunk
    let undone: Bool
    let reviewWidth: CGFloat

    private var decision: HunkDecision? { file.hunkDecisions?[hunk.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.none) {
            heading
            .padding(DLSSpacing.sm)
            .frame(width: reviewWidth, alignment: .leading)
            Divider()
            // Ranges remain in one continuous, GitHub-style unified diff.
            VStack(alignment: .leading, spacing: DLSSpacing.none) {
                lines(hunk.leadingContext, oldStart: hunk.oldRange.lowerBound - hunk.leadingContext.count,
                    newStart: hunk.newRange.lowerBound - hunk.leadingContext.count, marker: " ")
                lines(hunk.oldLines, oldStart: hunk.oldRange.lowerBound, newStart: nil, marker: "−")
                lines(hunk.newLines, oldStart: nil, newStart: hunk.newRange.lowerBound, marker: "+")
                lines(hunk.trailingContext, oldStart: hunk.oldRange.upperBound,
                    newStart: hunk.newRange.upperBound, marker: " ")
                if hunk.oldLines.isEmpty && hunk.newLines.isEmpty {
                    Text(file.before == nil ? "Empty file added" : "Empty file deleted")
                        .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                        .padding(DLSSpacing.sm)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Change \(hunk.id + 1) in \(file.path)")
    }

    private var heading: some View {
        HStack(spacing: DLSSpacing.sm) {
            Text("@@ −\(hunk.oldRange.lowerBound + 1),\(hunk.oldRange.count) +\(hunk.newRange.lowerBound + 1),\(hunk.newRange.count) @@")
                .dlsFont(.monoCaption)
            Text(undone ? "Undone" : decision == .accepted ? "Accepted" : decision == .rejected ? "Rejected" : "Needs review")
                .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func lines(_ lines: [String], oldStart: Int?, newStart: Int?, marker: String) -> some View {
        let color = marker == "−" ? theme.colors.danger : marker == "+" ? theme.colors.success : theme.colors.textSecondary
        return VStack(alignment: .leading, spacing: DLSSpacing.none) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: DLSSpacing.sm) {
                    Text(oldStart.map { "\($0 + index + 1)" } ?? "")
                        .foregroundStyle(theme.colors.textSecondary).frame(width: 36, alignment: .trailing)
                    Text(newStart.map { "\($0 + index + 1)" } ?? "")
                        .foregroundStyle(theme.colors.textSecondary).frame(width: 36, alignment: .trailing)
                    Text(marker).foregroundStyle(color).accessibilityHidden(true)
                    Text(line.hasSuffix("\n") ? String(line.dropLast()) : line)
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    if !line.hasSuffix("\n") {
                        Text("No newline").dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .font(theme.profile.font(size: theme.profile.codeSize, code: true))
                .padding(.horizontal, DLSSpacing.sm).padding(.vertical, DLSSpacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(marker == " " ? .clear : color.opacity(0.08))
            }
        }
    }

}

/// Actions stay outside both axes of the code scroll view.
struct InlineHunkActions: View {
    @Environment(AppStore.self) private var store
    let changesID: UUID
    let file: FileEdit
    let hunk: FileDiffHunk
    let undone: Bool

    private var decision: HunkDecision? { file.hunkDecisions?[hunk.id] }
    private var disabled: Bool { undone || store.sending || store.applyingFileUndo || store.savingReviewedFile }

    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            if decision != nil {
                Button("Reset", systemImage: "arrow.uturn.backward") { decide(nil) }
                    .help("Restore the agent’s change and mark this hunk as needing review")
            }
            Button("Reject", systemImage: "xmark") { decide(.rejected) }
                .disabled(decision == .rejected)
                .help("Restore the original text for this hunk")
            Button("Accept", systemImage: "checkmark") { decide(.accepted) }
                .disabled(decision == .accepted)
                .help("Keep the agent’s text for this hunk")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
    }

    private func decide(_ decision: HunkDecision?) {
        Task { await store.reviewHunk(hunk.id, decision: decision, path: file.path, changesID: changesID) }
    }
}
