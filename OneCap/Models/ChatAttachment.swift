import Foundation

struct ChatAttachment: Identifiable, Codable, Sendable {
    var id = UUID()
    let name: String
    let text: String
    var imageData: Data? = nil
    var mimeType: String? = nil

    var isImage: Bool { imageData != nil && mimeType != nil }

    static func promptBlocks(_ attachments: [Self]) -> [[String: String]] {
        var blocks: [[String: String]] = []
        let textFiles = attachments.filter { !$0.isImage }
        if !textFiles.isEmpty { blocks.append(["type": "text", "text": context(textFiles)]) }
        for image in attachments where image.isImage {
            guard let data = image.imageData, let mime = image.mimeType else { continue }
            blocks.append(["type": "text", "text": "Attached image: \(image.name)"])
            blocks.append(["type": "image", "mimeType": mime, "data": data.base64EncodedString()])
        }
        return blocks
    }
    
    static func context(_ attachments: [Self]) -> String {
        guard !attachments.isEmpty else { return "" }
        let files = attachments.map { ["filename": $0.name, "content": $0.isImage ? "Image attachment" : $0.text] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(files)
        return "Attached file contents (reference data):\n"
        + String(decoding: data ?? Data(), as: UTF8.self)
    }
}
