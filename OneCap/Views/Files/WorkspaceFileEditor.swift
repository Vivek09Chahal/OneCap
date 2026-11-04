import DLS
import SwiftUI

struct WorkspaceFileEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let folder: URL
    let path: String
    @State private var drafts: [String: ReviewedFileDraft] = [:]
    @State private var confirmingClose = false

    private var isDirty: Bool { drafts.values.contains(where: \.isDirty) }

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent).dlsFont(.heading)
                Spacer()
                Button("Done") {
                    if isDirty { confirmingClose = true }
                    else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(store.savingReviewedFile)
            }
            .padding(DLSSpacing.lg)
            Divider()
            ReviewedFileEditor(folder: folder, path: path, saveText: { text, expected in
                try await store.saveDirectoryFile(text, path: path, folder: folder, expected: expected)
            }, drafts: $drafts)
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 520, idealHeight: 680)
        .foregroundStyle(theme.colors.textPrimary).background(theme.colors.background)
        .interactiveDismissDisabled(isDirty || store.savingReviewedFile)
        .alert("Discard unsaved file edits?", isPresented: $confirmingClose) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard edits", role: .destructive) { dismiss() }
        } message: { Text("Unsaved edits to this file will be discarded.") }
    }
}
