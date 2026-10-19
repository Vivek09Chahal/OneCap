import AppKit
import DLS
import SwiftUI

struct ChatComposer<Leading: View, Trailing: View>: View {
    @Environment(\.dlsTheme) private var theme
    @FocusState private var inputFocused: Bool
    @Binding var draft: String
    let sending: Bool
    let stopping: Bool
    let canSend: Bool
    let status: String
    let send: () -> Void
    let stop: () -> Void
    var attachments: [ChatAttachment] = []
    var importingFiles = false
    var removeAttachment: (UUID) -> Void = { _ in }
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            if !attachments.isEmpty {
                ChatAttachmentStrip(attachments: attachments, remove: removeAttachment).disabled(sending)
            }
            TextField(
                "Message", text: $draft,
                prompt: Text("Ask anything, or start building…").foregroundStyle(theme.colors.textTertiary),
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(DLSTypography.chatInput)
                .foregroundStyle(theme.colors.textPrimary)
                .tint(theme.colors.accent)
                .focused($inputFocused)
                .lineLimit(2...8)
                .disabled(sending)
                .accessibilityLabel("Message")
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift), !press.modifiers.contains(.option) else {
                        return .ignored
                    }
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                       editor.hasMarkedText() { return .ignored }
                    if canSubmit {
                        let submittedDraft = draft
                        // Finish native text-input dispatch before clearing/disabling
                        // the editor or updating navigation and history state.
                        Task { @MainActor in
                            await Task.yield()
                            guard draft == submittedDraft, canSubmit else { return }
                            send()
                        }
                    }
                    return .handled
                }
                .help("Return to send · Shift-Return for a new line")
                .padding(.horizontal, DLSSpacing.sm)
                .padding(.top, DLSSpacing.xs)
            ChatComposerControls(
                sending: sending, stopping: stopping, canSubmit: canSubmit,
                importingFiles: importingFiles, send: send, stop: stop,
                leading: leading, trailing: trailing)
        }
        .help(status)
        .padding(DLSSpacing.md)
        .background(
            LinearGradient(colors: [theme.colors.composer, theme.colors.surface], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: DLSRadius.extraLarge))
        .overlay {
            RoundedRectangle(cornerRadius: DLSRadius.extraLarge)
                .stroke(inputFocused ? theme.colors.accent.opacity(0.6) : theme.colors.borderStrong.opacity(0.65), lineWidth: DLSSize.border)
        }
        .shadow(color: .black.opacity(inputFocused ? 0.12 : 0.06), radius: DLSSpacing.md, y: DLSSpacing.xs)
        .animation(.easeOut(duration: 0.15), value: inputFocused)
    }
    private var canSubmit: Bool {
        !sending && !importingFiles && canSend
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

}

struct ComposerSendButton: View {
    @Environment(\.dlsTheme) private var theme
    let sending: Bool
    let stopping: Bool
    let enabled: Bool
    let send: () -> Void
    let stop: () -> Void
    
    var body: some View {
        Button(action: sending ? stop : send) {
            Image(systemName: sending ? "stop.fill" : "arrow.up")
                .font(DLSTypography.navigationIcon)
                .foregroundStyle(sending || enabled ? theme.colors.onAccent : theme.colors.textTertiary)
                .frame(width: ChatLayout.sendButtonSize, height: ChatLayout.sendButtonSize)
                .background(sending || enabled ? theme.colors.accent : theme.colors.border, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(sending ? stopping : !enabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(
            sending ? (stopping ? "Stopping response" : "Stop response") : "Send message"
        )
        .help(sending ? "Stop response" : "Send message (Return or ⌘ Return)")
    }
}
