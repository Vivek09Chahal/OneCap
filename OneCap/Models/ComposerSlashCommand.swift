import Foundation

/// Slash commands occupy the first line; ordinary prose and paths stay untouched.
struct ComposerSlashQuery: Equatable {
    let command: String
    let argument: String?
    let range: Range<String.Index>

    static func active(in draft: String, at caret: String.Index? = nil) -> Self? {
        let caret = caret ?? draft.endIndex
        guard caret >= draft.startIndex, caret <= draft.endIndex,
              draft.first == "/" else { return nil }
        let end = draft.firstIndex(of: "\n") ?? draft.endIndex
        guard caret <= end else { return nil }
        let line = draft[..<end]
        let separator = line.firstIndex(where: \.isWhitespace)
        let command = String(line[draft.index(after: draft.startIndex)..<(separator ?? end)]).lowercased()
        guard command.allSatisfy(\.isLetter) else { return nil }
        let argument = separator.map { String(line[$0...]).trimmingCharacters(in: .whitespaces) }
        return Self(command: command, argument: argument, range: draft.startIndex..<end)
    }
}

struct ComposerSlashSuggestion: Identifiable, Equatable {
    enum Action: Equatable {
        case command(String)
        case model(option: String, value: String)
        case provider(UUID)
        case skill(UUID)
        case files, folder
    }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: Action
    var enabled = true
}

extension AppStore {
    func slashSuggestions(for query: ComposerSlashQuery) -> [ComposerSlashSuggestion] {
        if query.argument == nil {
            return [
                ComposerSlashSuggestion(id: "model", title: "/model", detail: "Choose a model", symbol: "cpu", action: .command("model")),
                ComposerSlashSuggestion(id: "skill", title: "/skill", detail: "Attach a skill to this message", symbol: "sparkles", action: .command("skill")),
                ComposerSlashSuggestion(id: "attach", title: "/attach", detail: "Attach files or a working folder", symbol: "paperclip", action: .command("attach")),
            ].filter { $0.id.hasPrefix(query.command) }
        }
        let filter = query.argument ?? ""
        let idle = !sending && !connecting && !acp.updatingConfiguration
        let rows: [ComposerSlashSuggestion]
        switch query.command {
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
