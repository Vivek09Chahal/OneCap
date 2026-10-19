import AppKit

@MainActor enum ChatClipboard {
    @discardableResult static func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        return clipboard.setString(text, forType: .string)
    }
    
    static func copyConversation(_ messages: [ChatMessage]) {
        copy(
            messages.filter { !$0.text.isEmpty }.map {
                "\($0.role == "user" ? "You" : "Assistant"):\n\($0.text)"
            }.joined(separator: "\n\n"))
    }
}
