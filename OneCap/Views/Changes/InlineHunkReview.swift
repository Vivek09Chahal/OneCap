import AppKit
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
    @State private var layout: FileReviewLayout?
    @State private var contentWidth: CGFloat = 0
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
                if let layout {
                    let hunks = layout.hunks
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
                            // Ranges remain in one continuous, GitHub-style unified diff.
                            LazyVStack(alignment: .leading, spacing: DLSSpacing.none) {
                                ForEach(layout.rows) { row in
                                    InlineDiffRow(row: row, decision: file.hunkDecisions?[row.hunkID],
                                        undone: changes.revertedAt != nil, reviewWidth: geometry.size.width)
                                }
                            }
                            // Include every hunk's natural width in the scrollable content size.
                            // A lazy stack can otherwise report only the viewport width while text overflows it.
                            .frame(width: max(geometry.size.width, contentWidth), alignment: .leading)
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
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(DLSSpacing.md)
                }
            }
        }
        .task(id: PreparationKey(source: FileReviewLayoutCache.Key(file: file), expanded: expanded, profile: theme.profile)) {
            guard expanded else { return }
            layout = nil
            do {
                let prepared = try await FileReviewLayoutCache.shared.layout(for: file)
                try Task.checkCancellation()
                let font = theme.profile.nsFont(size: theme.profile.codeSize, code: true)
                let width = await Self.measureWidth(prepared, font: font)
                try Task.checkCancellation()
                contentWidth = width
                layout = prepared
            } catch { /* A cancelled review must not publish stale rows. */ }
        }
        .onChange(of: expandAll) { _, value in expanded = value }
    }

    private struct PreparationKey: Equatable {
        let source: FileReviewLayoutCache.Key
        let expanded: Bool
        let profile: DLSVisualProfile
    }

    @concurrent private static func measureWidth(_ layout: FileReviewLayout, font: NSFont) async -> CGFloat {
        // Measure once, including offscreen lines, without geometry callbacks during scrolling.
        layout.rows.reduce(CGFloat(0)) { width, row in
            max(width, (row.text as NSString).size(withAttributes: [.font: font]).width
                + (row.isHeading ? 180 : row.missingNewline ? 240 : 140))
        }
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

private struct InlineDiffRow: View {
    @Environment(\.dlsTheme) private var theme
    let row: FileReviewLayout.Row
    let decision: HunkDecision?
    let undone: Bool
    let reviewWidth: CGFloat

    private var color: Color {
        row.marker == "−" ? theme.colors.danger : row.marker == "+" ? theme.colors.success : theme.colors.textSecondary
    }

    var body: some View {
        if row.isHeading {
            VStack(alignment: .leading, spacing: DLSSpacing.none) {
                HStack(spacing: DLSSpacing.sm) {
                    Text(row.text).dlsFont(.monoCaption)
                    Text(undone ? "Undone" : decision == .accepted ? "Accepted" : decision == .rejected ? "Rejected" : "Needs review")
                        .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                }
                .padding(DLSSpacing.sm)
                .frame(width: reviewWidth, alignment: .leading)
                Divider()
            }
        } else {
            HStack(alignment: .top, spacing: DLSSpacing.sm) {
                Text(row.oldLine.map(String.init) ?? "")
                    .foregroundStyle(theme.colors.textSecondary).frame(width: 36, alignment: .trailing)
                Text(row.newLine.map(String.init) ?? "")
                    .foregroundStyle(theme.colors.textSecondary).frame(width: 36, alignment: .trailing)
                Text(row.marker).foregroundStyle(color).accessibilityHidden(true)
                Text(row.text).textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                if row.missingNewline {
                    Text("No newline").dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                }
            }
            .font(theme.profile.font(size: theme.profile.codeSize, code: true))
            .padding(.horizontal, DLSSpacing.sm).padding(.vertical, DLSSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(row.marker == " " ? .clear : color.opacity(0.08))
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
