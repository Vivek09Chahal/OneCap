import AppKit
import DLS
import SwiftUI

struct MessageEditor: View {
    @Environment(\.dlsTheme) private var theme
    @Binding var text: String
    let canResend: Bool
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            TextField("Edit your message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DLSTypography.chatInput)
                .lineLimit(3...10)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) || press.modifiers.contains(.option),
                          let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                          !editor.hasMarkedText() else { return .ignored }
                    editor.insertText("\n", replacementRange: editor.selectedRange())
                    return .handled
                }
                .padding(DLSSpacing.lg)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: DLSRadius.medium).stroke(
                        theme.colors.borderStrong, lineWidth: DLSSize.border))
            HStack {
                Text("Replaces the response to this message.")
                    .font(DLSTypography.footnote).foregroundStyle(theme.colors.textSecondary)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Save & resend", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canResend || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .task { focused = true }
    }
}
