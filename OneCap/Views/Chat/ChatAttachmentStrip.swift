import DLS
import SwiftUI

struct ChatAttachmentStrip: View {
    @Environment(\.dlsTheme) private var theme
    let attachments: [ChatAttachment]
    var remove: ((UUID) -> Void)?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DLSSpacing.sm) {
                ForEach(attachments) { file in
                    HStack(spacing: DLSSpacing.xs) {
                        Image(systemName: "doc.text")
                        Text(file.name).lineLimit(1)
                        if let remove {
                            Button("Remove \(file.name)", systemImage: "xmark") { remove(file.id) }
                                .labelStyle(.iconOnly).buttonStyle(.plain)
                        }
                    }
                    .font(DLSTypography.caption)
                    .padding(DLSSpacing.sm)
                    .background(theme.colors.background, in: RoundedRectangle(cornerRadius: DLSRadius.small))
                    .help(file.name)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
