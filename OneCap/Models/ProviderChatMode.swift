import Foundation

enum ProviderChatMode: String, CaseIterable, Codable, Sendable {
    case ask, write, plan

    var title: String { rawValue.capitalized }

    var instruction: String {
        switch self {
        case .ask:
            "Ask mode: Answer the user's questions and explain relevant code. Inspect available context when useful; do not perform actions that change files or external state."
        case .write:
            "Write mode: Generate concrete code or suggested patches for the user's request. Workspace file tools are read-only; show proposed changes in your answer and never claim to have applied them."
        case .plan:
            "Plan mode: Inspect available context and produce an actionable implementation plan. Explain the steps, affected files, and validation. Do not implement changes or perform actions that change files or external state."
        }
    }
}
