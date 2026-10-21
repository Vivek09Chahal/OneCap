import DLS
import SwiftUI

struct QueuedMessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            HStack {
                Text(store.sending ? "Queued · sends after the current response" : "Queued messages · paused")
                    .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                Spacer()
                if !store.sending {
                    Button("Send queued messages") { store.sendNextQueuedMessage() }
                        .disabled(store.connecting || store.importingFiles || store.applyingFileUndo
                            || (store.chatUsesAgent ? !store.acp.sessionReady : store.selectedProvider == nil))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    ForEach(store.queuedMessages) { pending in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                                if !pending.message.text.isEmpty {
                                    Text(pending.message.text).lineLimit(2)
                                }
                                if let attachments = pending.message.attachments, !attachments.isEmpty {
                                    ChatAttachmentStrip(attachments: attachments)
                                }
                            }
                            Spacer(minLength: DLSSpacing.sm)
                            Button("Remove queued message", systemImage: "xmark") {
                                store.removeQueuedMessage(pending.id)
                            }.labelStyle(.iconOnly).buttonStyle(.plain)
                        }
                        .padding(DLSSpacing.sm)
                        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.small))
                    }
                }
            }
            .frame(maxHeight: 140)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(DLSTypography.callout)
    }
}
