import Foundation

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct ToolCall: Decodable {
                struct Function: Decodable {
                    let name: String
                    let arguments: String
                }
                let id: String
                let function: Function
            }
            let content: String?
            let tool_calls: [ToolCall]?
        }
        let message: Message
    }
    let choices: [Choice]
}
