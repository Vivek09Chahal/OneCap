import AppKit
import DLS
import PDFKit
import SwiftUI

struct ChatAttachmentStrip: View {
    let attachments: [ChatAttachment]
    var remove: ((UUID) -> Void)?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DLSSpacing.sm) {
                ForEach(attachments) { file in
                    ChatAttachmentChip(file: file, remove: remove)
                }
            }
        }
        .defaultScrollAnchor(alignment == .trailing ? .trailing : .leading, for: .alignment)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChatAttachmentChip: View {
    @Environment(\.dlsTheme) private var theme
    @State private var previewPresented = false
    let file: ChatAttachment
    let remove: ((UUID) -> Void)?

    private var hasPreview: Bool { file.isImage || file.pdfData != nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: DLSSpacing.xs) {
                if hasPreview {
                    Button { previewPresented = true } label: {
                        label
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(file.name)")
                    .popover(isPresented: $previewPresented) {
                        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                            HStack {
                                Text(file.name).font(DLSTypography.caption).lineLimit(1)
                                Spacer()
                                Button("Close preview", systemImage: "xmark") { previewPresented = false }
                                    .labelStyle(.iconOnly).buttonStyle(.plain)
                            }
                            if let data = file.pdfData {
                                ChatPDFPreview(data: data)
                            } else if let data = file.imageData, let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .padding(DLSSpacing.md)
                        .frame(width: 560, height: 480)
                    }
                } else {
                    label
                }
                if !file.isImage {
                    removeButton
                }
            }
            if file.isImage {
                removeButton
                    .padding(DLSSpacing.xs)
            }
        }
        .font(DLSTypography.caption)
        .padding(DLSSpacing.sm)
        .background(theme.colors.background, in: RoundedRectangle(cornerRadius: DLSRadius.small))
        .help(hasPreview ? "Preview \(file.name)" : file.name)
    }

    @ViewBuilder
    private var removeButton: some View {
        if let remove {
            Button("Remove \(file.name)", systemImage: "xmark") { remove(file.id) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .padding(file.isImage ? DLSSpacing.xs : 0)
                .background(file.isImage ? theme.colors.surface : .clear, in: Circle())
        }
    }

    private var label: some View {
        HStack(spacing: DLSSpacing.xs) {
            if file.isImage {
                ChatAttachmentThumbnail(file: file)
                    .overlay {
                        if remove != nil {
                            RoundedRectangle(cornerRadius: DLSRadius.small)
                                .strokeBorder(theme.colors.borderStrong, lineWidth: DLSSize.border)
                        }
                    }
            } else {
                Image(systemName: "doc.text")
                Text(file.name).lineLimit(1)
            }
        }
    }
}

private struct ChatAttachmentThumbnail: View {
    let file: ChatAttachment
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .frame(width: 120, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: DLSRadius.small))
            } else {
                Image(systemName: "photo")
                    .frame(width: 120, height: 90)
            }
        }
        .task(id: file.id) {
            if let data = file.imageData {
                thumbnail = NSImage(data: data)
            }
        }
    }
}

private struct ChatPDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
