// Compile against the app's Debug module and debug dylib, as with other UI fixtures.
import AppKit
import PDFKit
import SwiftUI
@testable import OneCap

@main struct VerifyChatExport {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let attachments = [
            ChatAttachment(name: "source.swift", text: "let fence = \"```\""),
            ChatAttachment(name: "image.png", text: "", imageData: Data([1, 2, 3]), mimeType: "image/png"),
        ]
        let source = (1...600).map { "Line \($0): long transcript text." }.joined(separator: "\n")
            + "\nFINAL_TRANSCRIPT_MARKER"
        let messages = [
            ChatMessage(role: "user", text: "Question 日本語", attachments: attachments),
            ChatMessage(role: "assistant", text: "## Answer\n\n```swift\nprint(42)\n```\n\n" + source, replyState: .stopped),
        ]
        let transcript = ChatExport(title: "Export / check: title", messages: messages)
        precondition(!transcript.filename.contains("/") && !transcript.filename.contains(":"))
        precondition(transcript.markdown.contains("````\nlet fence"))
        precondition(transcript.markdown.contains("Reply status: stopped"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ChatExport.self, from: transcript.data(for: .json))
        precondition(restored.messages == messages && restored.version == 1)
        let data = try transcript.data(for: .pdf)
        let pdf = PDFDocument(data: data)!
        precondition(pdf.pageCount > 1)
        precondition(pdf.string?.contains("FINAL_TRANSCRIPT_MARKER") == true)
        precondition(pdf.string?.contains("Question 日本語") == true)
        try data.write(to: URL(fileURLWithPath: "/tmp/OneCap-export-preview.pdf"))
        let page = pdf.page(at: 0)!
        let image = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/OneCap-export-preview.png"))
        }

        let store = AppStore(stateURL: URL(fileURLWithPath: "/tmp/OneCap-export-fixture-\(UUID())/state.json"))
        store.messages = [messages[0]]
        store.checkpointConversation(touch: false)
        store.messages.append(messages[1])
        store.draft = "UNSENT_SECRET"
        store.workspace = URL(fileURLWithPath: "/private/WORKSPACE_SECRET")
        let live = store.exportTranscript(store.conversationID)
        precondition(live.messages == messages)
        let json = String(decoding: try live.data(for: .json), as: UTF8.self)
        precondition(!json.contains("UNSENT_SECRET") && !json.contains("WORKSPACE_SECRET"))
        let host = NSHostingView(rootView: HStack {
            ChatExportMenu(conversationID: store.conversationID)
            ChatShareButton(transcript: live)
        }.environment(store))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        print("PASS: Markdown, JSON attachment round trip, Unicode PDF pagination (\(pdf.pageCount) pages), live snapshot, draft exclusion, export/share controls")
    }
}
