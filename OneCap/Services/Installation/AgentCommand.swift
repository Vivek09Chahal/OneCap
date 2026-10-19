import Foundation

struct AgentCommand: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
}
