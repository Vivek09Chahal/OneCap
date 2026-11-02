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

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack(spacing: DLSSpacing.xs) {
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
                Spacer(minLength: DLSSpacing.none)
            }
            .padding(.horizontal, DLSSpacing.sm)
            Divider()
            switch selection {
            case .directory:
                if let folder = store.workspace {
                    WorkspaceFileTreeSidebar(folder: folder).id(folder)
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
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.colors.borderStrong).frame(width: DLSSize.border)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
