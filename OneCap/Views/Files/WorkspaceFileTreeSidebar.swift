import DLS
import SwiftUI

struct WorkspaceFileTreeSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    let folder: URL
    @State private var tree = FolderTreeModel()
    @State private var revision = UUID()

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack(spacing: DLSSpacing.sm) {
                Label(folder.lastPathComponent, systemImage: "folder")
                    .font(DLSTypography.captionStrong).lineLimit(1)
                    .truncationMode(.middle).help(folder.path)
                Spacer(minLength: DLSSpacing.sm)
                Button("Refresh files", systemImage: "arrow.clockwise") { revision = UUID() }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .disabled(tree.refreshing || !tree.loading.isEmpty).help("Refresh folder contents")
            }
            .padding(DLSSpacing.md)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DLSSpacing.none) {
                    if tree.loading.contains(folder) {
                        ProgressView().controlSize(.small).padding(DLSSpacing.lg)
                    } else if let error = tree.errors[folder] {
                        errorNotice(error, folder: folder, depth: 0)
                    } else if tree.rows.isEmpty {
                        Text("This folder is empty")
                            .font(DLSTypography.caption)
                            .foregroundStyle(theme.colors.textSecondary).padding(DLSSpacing.lg)
                    }
                    ForEach(tree.rows) { row in
                        FolderTreeRow(
                            entry: row.entry, depth: row.depth,
                            expanded: tree.expanded.contains(row.id),
                            loading: tree.loading.contains(row.id)
                        ) { Task { await tree.toggle(row.entry) } }
                        if tree.expanded.contains(row.id) {
                            if let error = tree.errors[row.id] {
                                errorNotice(error, folder: row.id, depth: row.depth + 1)
                            } else if tree.children[row.id]?.isEmpty == true {
                                Text("Empty folder").font(DLSTypography.footnote)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .padding(.leading, DLSSpacing.xxl + CGFloat(row.depth + 1) * DLSSpacing.lg)
                                    .padding(.vertical, DLSSpacing.xs)
                            }
                        }
                    }
                }
                .padding(.vertical, DLSSpacing.sm)
            }
        }
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.sidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.colors.borderStrong).frame(width: DLSSize.border)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .task(id: RefreshRequest(folder: folder, manual: revision, files: store.fileTreeRevision)) {
            await tree.open(folder)
        }
    }

    private struct RefreshRequest: Equatable {
        let folder: URL
        let manual: UUID
        let files: UUID
    }

    private func errorNotice(_ error: String, folder: URL, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xs) {
            Text(error).font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
            Button("Try again") { Task { await tree.load(folder) } }.buttonStyle(.link)
        }
        .padding(.leading, DLSSpacing.md + CGFloat(depth) * DLSSpacing.lg)
        .padding([.vertical, .trailing], DLSSpacing.md)
    }
}
