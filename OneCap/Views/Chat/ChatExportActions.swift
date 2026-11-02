import AppKit
import CoreTransferable
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct ChatShareItem: Transferable {
    let transcript: ChatExport

    func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCap-Share-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(transcript.filename).appendingPathExtension("md")
        try Data(transcript.markdown.utf8).write(to: url, options: .atomic)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: ChatExport.Format.markdown.contentType) { item in
            // Keep the temporary source alive while the system transfers its copy.
            return SentTransferredFile(try item.temporaryFileURL(), allowAccessingOriginalFile: false)
        }
    }
}

struct ChatShareButton: View {
    let transcript: ChatExport
    var toolbarStyle = false
    @State private var shareAnchor = NSView(frame: .zero)
    @State private var sharingPicker: NSSharingServicePicker?

    var body: some View {
        if toolbarStyle {
            Button {
                share()
            } label: {
                ToolbarIcon(symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .frame(width: ChatLayout.toolbarControlSize, height: ChatLayout.toolbarControlSize)
            .background(ChatShareAnchor(view: shareAnchor))
            .accessibilityLabel("Share Chat")
            .disabled(transcript.messages.isEmpty)
            .help("Share a Markdown copy of this chat")
        } else {
            ShareLink(item: ChatShareItem(transcript: transcript), preview: SharePreview(transcript.title)) {
                Label("Share Chat", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Chat")
            .disabled(transcript.messages.isEmpty)
            .help("Share a Markdown copy of this chat")
        }
    }

    @MainActor private func share() {
        guard let url = try? ChatShareItem(transcript: transcript).temporaryFileURL(),
              shareAnchor.window != nil else { return }
        let picker = NSSharingServicePicker(items: [url])
        sharingPicker = picker
        picker.show(relativeTo: shareAnchor.bounds, of: shareAnchor, preferredEdge: .minY)
    }
}

/// The system sharing picker must use the clicked toolbar control as its source rect.
private struct ChatShareAnchor: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ChatExportMenu: View {
    @Environment(AppStore.self) private var store
    let conversationID: UUID
    var toolbarStyle = false

    var body: some View {
        if toolbarStyle {
            ToolbarIconMenu(title: "Export Chat", symbol: "square.and.arrow.down") {
                exportItems
            }
            .disabled(store.exportTranscript(conversationID).messages.isEmpty)
            .help("Save this chat as Markdown, PDF, or JSON")
        } else {
            Menu {
                exportItems
            } label: {
                Label("Export Chat", systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel("Export Chat")
            .disabled(store.exportTranscript(conversationID).messages.isEmpty)
            .help("Save this chat as Markdown, PDF, or JSON")
        }
    }

    private var exportItems: some View {
        ForEach(ChatExport.Format.allCases, id: \.self) { format in
            Button("\(format.name)…") {
                // Capture now, so navigation or streaming cannot change an open export.
                let transcript = store.exportTranscript(conversationID)
                Task { await save(transcript, as: format) }
            }
        }
    }

    @MainActor private func save(_ transcript: ChatExport, as format: ChatExport.Format) async {
        let panel = NSSavePanel()
        panel.title = "Export Chat"
        panel.prompt = "Export"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = transcript.filename + "." + format.fileExtension
        let response = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK, let url = panel.url else { return }
        do {
            try transcript.data(for: format).write(to: url, options: .atomic)
        } catch {
            store.error = "Could not export chat: \(error.localizedDescription)"
        }
    }
}

struct ChatExportCommandTarget {
    let conversationID: UUID
    let store: AppStore
}

private struct ChatExportCommandKey: FocusedValueKey { typealias Value = ChatExportCommandTarget }
extension FocusedValues {
    var chatExportTarget: ChatExportCommandTarget? {
        get { self[ChatExportCommandKey.self] }
        set { self[ChatExportCommandKey.self] = newValue }
    }
}
