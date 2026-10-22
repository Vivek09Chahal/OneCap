import DLS
import SwiftUI

struct MessageActions: View {
    @Environment(\.dlsTheme) private var theme
    let text: String
    let canEdit: Bool
    let edit: () -> Void
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: DLSSpacing.xs) {
            Button {
                copied = ChatClipboard.copy(text)
            } label: {
                Label {
                    Text(copied ? "Copied" : "Copy")
                } icon: {
                    if copied {
                        Image(systemName: "checkmark")
                    } else {
                        Image("Copybutton")
                            .resizable()
                            .scaledToFit()
                            .frame(width: DLSSize.iconCompact, height: DLSSize.iconCompact)
                    }
                }
            }
            .disabled(text.isEmpty)
            .help(copied ? "Copied" : "Copy message")
            if canEdit {
                Button(action: edit) {
                    Label {
                        Text("Edit")
                    } icon: {
                        Image("edit")
                            .resizable()
                            .scaledToFit()
                            .frame(width: DLSSize.iconCompact, height: DLSSize.iconCompact)
                    }
                }
                .help("Edit the latest user message")
            }
        }
        .buttonStyle(MessageActionStyle())
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

private struct MessageActionStyle: ButtonStyle {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
            .foregroundStyle(hovered || configuration.isPressed ? theme.colors.textPrimary : theme.colors.textSecondary)
            .background(
                configuration.isPressed ? theme.colors.selection : (hovered ? theme.colors.surface : .clear),
                in: RoundedRectangle(cornerRadius: DLSRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: DLSRadius.small))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovered = $0 }
    }
}
