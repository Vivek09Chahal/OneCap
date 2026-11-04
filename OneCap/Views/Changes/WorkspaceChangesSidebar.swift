import DLS
import SwiftUI

enum WorkspacePanelTab: String, CaseIterable, Identifiable {
    case directory = "Directory"
    case changes = "Changed files"
    var id: Self { self }
    @MainActor @ViewBuilder var icon: some View {
        switch self {
        case .directory: AppIcon(systemName: "folder")
        case .changes: AppIcon("GitBranch")
        }
    }
}

struct WorkspaceChangesSidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var selection: WorkspacePanelTab
    @State private var git: WorkspaceGitStatus?
    @State private var sourceControlVisible = false

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack(spacing: DLSSpacing.xs) {
                if let folder = store.workspace {
                    Text(folder.lastPathComponent)
                        .dlsFont(.captionStrong)
                        .lineLimit(1).truncationMode(.middle)
                        .help(folder.path)
                    if let branch = git?.branch {
                        Text(branch)
                            .dlsFont(.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, DLSSpacing.sm)
                            .padding(.vertical, DLSSpacing.xs)
                            .background(theme.colors.textSecondary.opacity(0.08), in: Capsule())
                            .help("Current Git branch: \(branch)")
                    }
                }
                Spacer(minLength: DLSSpacing.sm)
                if store.workspace != nil {
                    Button { sourceControlVisible = true } label: {
                        AppIcon(systemName: "arrow.triangle.branch")
                            .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
                    }
                    .buttonStyle(.plain).help("Source Control")
                    .accessibilityLabel("Source Control")
                }
                ForEach(WorkspacePanelTab.allCases) { tab in
                    Button { selection = tab } label: {
                        tab.icon
                            .font(DLSTypography.navigationIcon)
                            .foregroundStyle(selection == tab ? theme.colors.accent : theme.colors.textSecondary)
                            .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    .help(tab.rawValue)
                }
            }
            .padding(.leading, DLSSpacing.md)
            .padding(.trailing, DLSSpacing.sm)
            Divider()
            switch selection {
            case .directory:
                if let folder = store.workspace {
                    WorkspaceFileTreeSidebar(folder: folder, git: git).id(folder)
                } else {
                    VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                        Text("No folder selected").dlsFont(.heading)
                        Text("Choose a project folder to browse its files.")
                            .dlsFont(.callout)
                            .foregroundStyle(theme.colors.textSecondary)
                        Button("Choose folder…") {
                            Task {
                                if let folder = await WorkspaceFolderPicker.choose(),
                                   !store.sending, !store.applyingFileUndo {
                                    store.selectWorkspace(folder)
                                }
                            }
                        }
                        .disabled(store.sending || store.applyingFileUndo)
                    }
                    .padding(DLSSpacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            case .changes:
                SessionChangesSidebar()
            }
        }
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.sidebar)
        .sheet(isPresented: $sourceControlVisible) {
            if let folder = store.workspace { WorkspaceGitView(folder: folder) }
        }
        .task(id: GitRefresh(folder: store.workspace, revision: store.fileTreeRevision)) {
            git = nil
            guard let folder = store.workspace else { return }
            let status = await WorkspaceGitStatus.read(in: folder)
            guard !Task.isCancelled else { return }
            git = status
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.colors.borderStrong).frame(width: DLSSize.border)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private struct GitRefresh: Equatable {
        let folder: URL?
        let revision: UUID
    }
}
