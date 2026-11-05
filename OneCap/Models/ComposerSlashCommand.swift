import Foundation

/// Slash commands follow the caret on any line; ordinary paths and URLs stay untouched.
struct ComposerSlashQuery: Equatable {
    let command: String
    let argument: String?
    let range: Range<String.Index>

    func occurrencePrefix(in draft: String) -> String {
        guard draft.indices.contains(range.lowerBound) else { return "" }
        return String(draft[...range.lowerBound])
    }

    static func active(in draft: String, at caret: String.Index? = nil) -> Self? {
        let caret = caret ?? draft.endIndex
        guard caret == draft.endIndex || draft.indices.contains(caret) else { return nil }
        let prefix = draft[..<caret]
        let lineStart = prefix.lastIndex(of: "\n").map { draft.index(after: $0) } ?? draft.startIndex
        let line = draft[lineStart..<caret]
        // A command begins at a word boundary, never inside a URL or file path.
        guard let start = line.indices.reversed().first(where: {
            draft[$0] == "/" && ($0 == lineStart || draft[draft.index(before: $0)].isWhitespace)
        }) else { return nil }
        let token = draft[draft.index(after: start)..<caret]
        let separator = token.firstIndex(where: \.isWhitespace)
        let command = String(token[..<(separator ?? caret)]).lowercased()
        guard command.allSatisfy(\.isLetter) else { return nil }
        let argument = separator.map { String(token[$0...]).trimmingCharacters(in: .whitespaces) }
        guard !command.isEmpty || argument == nil else { return nil }
        // Only replace what precedes the caret, preserving text on both sides.
        return Self(command: command, argument: argument, range: start..<caret)
    }
}

struct ComposerSlashSuggestion: Identifiable, Equatable {
    enum Action: Equatable {
        case command(String)
        case model(option: String, value: String)
        case provider(UUID)
        case skill(UUID)
        case files, folder, clear
    }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: Action
    var enabled = true
}

extension AppStore {
    private var clearChatSuggestion: ComposerSlashSuggestion {
        ComposerSlashSuggestion(id: "clear", title: "/clear", detail: "Start a new chat; keep this conversation in history",
            symbol: "square.and.pencil", action: .clear, enabled: !applyingFileUndo && !savingReviewedFile)
    }

    func slashSuggestions(for query: ComposerSlashQuery) -> [ComposerSlashSuggestion] {
        if query.argument == nil {
            return [
                ComposerSlashSuggestion(id: "model", title: "/model", detail: "Choose a model", symbol: "cpu", action: .command("model")),
                ComposerSlashSuggestion(id: "skill", title: "/skill", detail: "Attach a skill to this message", symbol: "sparkles", action: .command("skill")),
                ComposerSlashSuggestion(id: "attach", title: "/attach", detail: "Attach files or a working folder", symbol: "paperclip", action: .command("attach")),
                clearChatSuggestion,
            ].filter { $0.id.hasPrefix(query.command) }
        }
        let filter = query.argument ?? ""
        let idle = !sending && !connecting && !acp.updatingConfiguration
        let rows: [ComposerSlashSuggestion]
        switch query.command {
        case "clear":
            return filter.isEmpty ? [clearChatSuggestion] : []
        case "model":
            if chatUsesAgent {
                rows = acp.sessionOptions.filter(\.isModelSelector).flatMap { option in
                    option.choices.map { choice in
                        ComposerSlashSuggestion(id: "\(option.id):\(choice.id)", title: choice.name,
                            detail: choice.id == option.currentValue ? "Current model" : choice.detail ?? option.name,
                            symbol: "cpu", action: .model(option: option.id, value: choice.id),
                            enabled: idle && acp.sessionReady)
                    }
                }
            } else {
                rows = providers.map { provider in
                    ComposerSlashSuggestion(id: provider.id.uuidString, title: provider.model,
                        detail: provider.name, symbol: "cpu", action: .provider(provider.id), enabled: idle)
                }
            }
        case "skill":
            rows = skills.filter { skill in
                var available = skill
                available.enabled = true
                return available.applies(to: workspace)
            }.map { skill in
                ComposerSlashSuggestion(id: skill.id.uuidString, title: skill.name,
                    detail: skill.project == nil ? "Shared skill · this message" : "Project skill · this message",
                    symbol: "sparkles", action: .skill(skill.id), enabled: !importingFiles)
            }
        case "attach":
            rows = [
                ComposerSlashSuggestion(id: "files", title: "Files…", detail: "Attach images or text files", symbol: "paperclip", action: .files, enabled: !importingFiles),
                ComposerSlashSuggestion(id: "folder", title: "Working folder…", detail: "Choose the project folder", symbol: "folder", action: .folder, enabled: idle && !importingFiles),
            ]
        default: rows = []
        }
        return rows.filter { filter.isEmpty || $0.title.localizedStandardContains(filter) || $0.detail.localizedStandardContains(filter) }
    }
}
