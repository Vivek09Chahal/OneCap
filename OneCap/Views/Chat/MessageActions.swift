import DLS
import SwiftUI

struct MessageActions: View {
    @Environment(\.dlsTheme) private var theme
    let text: String
    let canEdit: Bool
    let edit: () -> Void
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: DLSSpacing.md) {
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                copied = ChatClipboard.copy(text)
            }
            .disabled(text.isEmpty)
            .help(copied ? "Copied" : "Copy message")
            if canEdit {
                Button("Edit", systemImage: "pencil", action: edit)
                    .help("Edit the latest user message")
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .font(DLSTypography.navigationIcon)
        .foregroundStyle(theme.colors.textSecondary)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
