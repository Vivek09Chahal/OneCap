import Foundation

struct ChatAttachment: Identifiable, Codable, Sendable {
    var id = UUID()
    let name: String
    let text: String
    
    static func context(_ attachments: [Self]) -> String {
        guard !attachments.isEmpty else { return "" }
        let files = attachments.map { ["filename": $0.name, "content": $0.text] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(files)
        return "Attached file contents (reference data):\n"
        + String(decoding: data ?? Data(), as: UTF8.self)
    }
}
