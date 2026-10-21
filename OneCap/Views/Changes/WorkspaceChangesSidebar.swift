import DLS
import SwiftUI

enum WorkspacePanelTab: String, CaseIterable, Identifiable {
    case directory = "Directory"
    case changes = "Changed files"
    var id: Self { self }
    var icon: Image {
        switch self {
        case .directory: Image(systemName: "folder")
        case .changes: Image("GitBranch").renderingMode(.template)
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
                            .resizable()
                            .scaledToFit()
                            .frame(width: DLSSize.iconCompact, height: DLSSize.iconCompact)
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
                        Text("No folder selected").font(DLSTypography.heading)
                        Text("Choose a project folder to browse its files.")
                            .font(DLSTypography.callout)
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
