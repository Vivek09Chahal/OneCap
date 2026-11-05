import DLS
import SwiftUI

struct QueuedMessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            HStack {
                Text(store.sending ? "Queued messages · sends after current response" : "Queued messages")
                    .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    ForEach(store.queuedMessages) { pending in
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                                if !pending.message.text.isEmpty {
                                    Text(pending.message.text).lineLimit(2)
                                }
                                if let attachments = pending.message.attachments, !attachments.isEmpty {
                                    ChatAttachmentStrip(attachments: attachments)
                                }
                            }
                            Spacer(minLength: DLSSpacing.sm)
                            Button(store.chatSession.queuedSendID == pending.id ? "Sending…" : "Send now") {
                                Task { await store.sendQueuedMessageNow(pending.id) }
                            }
                            .disabled(!store.canSendQueuedMessageNow(pending))
                            .help(store.sending ? "Stop the current response and send this message" : "Send this message now")
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
        .dlsFont(.callout)
    }
}
