import DLS
import SwiftUI

struct WorkspaceFileTreeSidebar: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    let folder: URL
    @State private var tree = FolderTreeModel()
    @State private var query = ""
    @State private var openedFile: FolderEntry?
    @AppStorage("directory.showHidden") private var showHidden = true

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack(spacing: DLSSpacing.sm) {
                AppIcon(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.textSecondary)
                TextField("Filter by name…", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("Filter files by name")
                if !query.isEmpty {
                    Button { query = "" } label: { AppIcon(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, DLSSpacing.md)
            .padding(.vertical, DLSSpacing.sm)
            .background(theme.colors.textSecondary.opacity(0.08), in: Capsule())
            .padding(.horizontal, DLSSpacing.sm)
            .padding(.top, DLSSpacing.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DLSSpacing.none) {
                    if tree.loading.contains(folder) {
                        ProgressView().controlSize(.small).padding(DLSSpacing.lg)
                    } else if let error = tree.errors[folder] {
                        errorNotice(error, folder: folder, depth: 0)
                    } else {
                        let rows = tree.visibleRows(query: query, showHidden: showHidden)
                        if rows.isEmpty {
                            Text(query.isEmpty ? "This folder is empty" : "No matching files")
                                .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                                .padding(DLSSpacing.lg)
                        }
                        ForEach(groups(rows)) { group in
                            if let title = group.title {
                                Text(title).dlsFont(.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .padding(.horizontal, DLSSpacing.md)
                                    .padding(.top, DLSSpacing.lg).padding(.bottom, DLSSpacing.sm)
                            }
                            ForEach(group.rows) { row in
                                FolderTreeRow(
                                    entry: row.entry, depth: row.depth,
                                    expanded: tree.expanded.contains(row.id) || !query.isEmpty,
                                    loading: tree.loading.contains(row.id)
                                ) {
                                    if row.entry.canExpand { Task { await tree.toggle(row.entry) } }
                                    else if !row.entry.isDirectory { openFile(row.entry) }
                                }
                                if tree.expanded.contains(row.id), let error = tree.errors[row.id] {
                                    errorNotice(error, folder: row.id, depth: row.depth + 1)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, DLSSpacing.sm)
            }
            footer
        }
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.sidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.colors.borderStrong).frame(width: DLSSize.border)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .sheet(item: $openedFile) { entry in
            WorkspaceFileEditor(folder: folder, path: entry.relativePath(in: folder))
        }
        .task(id: RefreshRequest(folder: folder, files: store.fileTreeRevision)) {
            await tree.open(folder)
        }
    }

    private func openFile(_ entry: FolderEntry) {
        let path = entry.relativePath(in: folder)
        if let changes = store.fileChanges.last(where: {
            $0.folder.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath()
                && $0.files.contains { $0.path == path }
        }) {
            store.reviewFileChanges(changes, path: path)
        } else { openedFile = entry }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            Divider()
            Toggle("Show hidden files", isOn: $showHidden)
                .toggleStyle(.checkbox).dlsFont(.caption)
        }
        .foregroundStyle(theme.colors.textSecondary).padding(DLSSpacing.md)
    }

    private struct Group: Identifiable {
        let id: Int
        let title: String?
        var rows: [FolderTreeModel.Row]
    }

    private func groups(_ rows: [FolderTreeModel.Row]) -> [Group] {
        var result = [Group(id: 0, title: nil, rows: []), Group(id: 1, title: "Files", rows: []),
                      Group(id: 2, title: "Hidden", rows: [])]
        var section = 0
        for row in rows {
            if row.depth == 0 {
                section = row.entry.name.hasPrefix(".") ? 2 : row.entry.isDirectory ? 0 : 1
            }
            result[section].rows.append(row)
        }
        return result.filter { !$0.rows.isEmpty }
    }

    private struct RefreshRequest: Equatable {
        let folder: URL
        let files: UUID
    }

    private func errorNotice(_ error: String, folder: URL, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xs) {
            Text(error).dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
            Button("Try again") { Task { await tree.load(folder) } }.buttonStyle(.link)
        }
        .padding(.leading, DLSSpacing.md + CGFloat(depth) * DLSSpacing.lg)
        .padding([.vertical, .trailing], DLSSpacing.md)
    }
}
