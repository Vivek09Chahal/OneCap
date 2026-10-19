import DLS
import SwiftUI

/// Compact working-folder control inside the composer's lower row.
struct ChatWorkspaceBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    
    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            ComposerOptionsButton(
                enabled: !store.sending && !store.connecting && !store.importingFiles
                && !store.acp.updatingConfiguration,
                label: {
                    Image(systemName: "plus").font(DLSTypography.navigationIcon)
                        .frame(width: ChatLayout.sendButtonSize, height: ChatLayout.sendButtonSize)
                        .contentShape(Rectangle())
                },
                content: { dismiss in
                    ComposerOptionsList(rowCount: 2, headingCount: 0) {
                        ComposerOptionRow(title: "Attach file…", selected: false) {
                            dismiss()
                            Task {
                                let conversation = store.conversationID
                                let files = await WorkspaceFolderPicker.chooseFiles()
                                if !files.isEmpty, store.conversationID == conversation {
                                    await store.attachFiles(files)
                                }
                            }
                        }
                        ComposerOptionRow(title: "Attach folder…", selected: false) {
                            dismiss()
                            chooseFolder()
                        }
                    }
                }
            )
            .accessibilityLabel("Add attachment")
            .help("Attach a text file or working folder")
            
            if let folder = store.workspace {
                ComposerOptionsButton(
                    enabled: !store.sending && !store.connecting && !store.acp.updatingConfiguration,
                    label: {
                        Label(folder.lastPathComponent, systemImage: "folder")
                            .lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                    },
                    content: { dismiss in
                        ComposerOptionsList(rowCount: 2, headingCount: 1) {
                            Text(folder.path).font(DLSTypography.caption).lineLimit(2)
                                .padding(.horizontal, DLSSpacing.sm)
                            ComposerOptionRow(title: "Change folder…", selected: false) {
                                dismiss()
                                chooseFolder()
                            }
                            ComposerOptionRow(title: "Remove folder", selected: false) {
                                dismiss()
                                store.selectWorkspace(nil)
                            }
                        }
                    }
                )
                .help(folder.path)
            }
        }
        .font(DLSTypography.caption)
        .foregroundStyle(theme.colors.textSecondary)
        .disabled(
            store.sending || store.connecting || store.importingFiles || store.acp.updatingConfiguration)
    }
    
    private func chooseFolder() {
        Task {
            if let folder = await WorkspaceFolderPicker.choose(), !store.sending,
               !store.connecting, !store.acp.updatingConfiguration
            {
                store.selectWorkspace(folder)
            }
        }
    }
}
