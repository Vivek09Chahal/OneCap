import DLS
import SwiftUI

struct ChatCodeBlock: View {
    @Environment(\.dlsTheme) private var theme
    let source: String
    let language: String?
    @State private var highlighted: AttributedString?
    @State private var wrapsLines = false
    @State private var copied = false

    private var languageLabel: String {
        guard let language, !language.isEmpty else { return "Code" }
        return ["swift": "Swift", "css": "CSS", "html": "HTML", "xml": "XML", "json": "JSON",
                "js": "JavaScript", "javascript": "JavaScript", "ts": "TypeScript", "typescript": "TypeScript",
                "py": "Python", "python": "Python", "sh": "Shell", "bash": "Bash", "zsh": "Shell",
                "sql": "SQL", "yaml": "YAML", "yml": "YAML", "text": "Plain text", "plaintext": "Plain text",
                "c": "C", "cpp": "C++", "csharp": "C#", "cs": "C#", "go": "Go", "rust": "Rust",
                "jsx": "JSX", "tsx": "TSX", "md": "Markdown", "markdown": "Markdown"][language.lowercased()] ?? language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(languageLabel, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 12)
                Button { wrapsLines.toggle() } label: {
                    Image(systemName: "arrow.turn.down.left")
                        .foregroundStyle(wrapsLines ? theme.colors.accent : theme.colors.textSecondary)
                }
                .help(wrapsLines ? "Scroll long code lines" : "Wrap long code lines")
                .accessibilityLabel("Wrap code lines")
                .accessibilityValue(wrapsLines ? "On" : "Off")
                Button {
                    copied = ChatClipboard.copy(source)
                } label: {
                    if copied {
                        Image(systemName: "checkmark")
                    } else {
                        Image("Copybutton")
                            .resizable()
                            .scaledToFit()
                            .frame(width: DLSSize.iconCompact, height: DLSSize.iconCompact)
                    }
                }
                .foregroundStyle(copied ? theme.colors.success : theme.colors.textSecondary)
                .help(copied ? "Copied" : "Copy code")
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
                .disabled(source.isEmpty)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            if wrapsLines {
                codeText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ScrollView(.horizontal) {
                    codeText.fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(theme.colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task(id: [source, language ?? "", theme.rawValue]) {
            highlighted = nil
            // Coalesce streamed chunks instead of highlighting every token.
            do {
                try await Task.sleep(for: .milliseconds(100))
                let text = try await FileSyntaxHighlighter.shared.code(source, language: language, dark: theme == .dark)
                try Task.checkCancellation()
                highlighted = text
            } catch { /* Keep selectable plain code if highlighting fails or is cancelled. */ }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private var codeText: some View {
        Text(highlighted ?? AttributedString(source))
            .font(.system(size: 13, weight: .light, design: .monospaced))
            .lineSpacing(6)
            .foregroundStyle(theme.colors.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
