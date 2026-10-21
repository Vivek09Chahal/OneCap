import DLS
import SwiftUI

struct ChatMessageRow: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    let message: ChatMessage
    let thinkingTime: ThinkingTime?
    let canEdit: Bool
    let isEditing: Bool
    @Binding var editedText: String
    let canResend: Bool
    let edit: () -> Void
    let saveEdit: () -> Void
    let cancelEdit: () -> Void
    private var isUser: Bool { message.role == "user" }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            HStack(alignment: .top, spacing: DLSSpacing.none) {
                if isUser { Spacer(minLength: DLSSpacing.huge) }
                VStack(alignment: isUser ? .trailing : .leading, spacing: DLSSpacing.sm) {
                    if isEditing {
                        MessageEditor(
                            text: $editedText, canResend: canResend, save: saveEdit, cancel: cancelEdit)
                    } else {
                        if let files = message.attachments, !files.isEmpty {
                            ChatAttachmentStrip(attachments: files)
                        }
                        if !message.text.isEmpty {
                            ChatMessageText(source: message.text)
                                .font(DLSTypography.chatBody)
                                .lineSpacing(DLSSpacing.xs)
                                .foregroundStyle(theme.colors.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, isUser ? DLSSpacing.lg : DLSSpacing.none)
                                .padding(.vertical, isUser ? DLSSpacing.md : DLSSpacing.none)
                                .background(
                                    isUser ? theme.colors.accentSubtle : .clear,
                                    in: RoundedRectangle(cornerRadius: DLSRadius.large)
                                )
                                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                                .contextMenu {
                                    Button("Copy", systemImage: "doc.on.doc") { ChatClipboard.copy(message.text) }
                                    if canEdit { Button("Edit", systemImage: "pencil", action: edit) }
                                }
                        }
                        if message.replyState == .stopped || message.replyState == .failed {
                            Text(message.replyState == .stopped ? "Response stopped" : "Response failed")
                                .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                        }
                        if !isUser, !message.text.isEmpty {
                            MessageActions(text: message.text, canEdit: canEdit, edit: edit)
                        }
                    }
                }
                .frame(
                    maxWidth: isUser ? ChatLayout.userMessageWidth : .infinity,
                    alignment: isUser ? .trailing : .leading)
            }
            if !isUser, let id = message.changeSetID,
               let changes = store.fileChanges.first(where: { $0.id == id }) {
                FileChangesSummary(changes: changes)
            }
            if let notice = message.changeTrackingNotice {
                Text(notice).font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
            }
            if isUser, !isEditing, thinkingTime != nil || !message.text.isEmpty {
                HStack(alignment: .center, spacing: DLSSpacing.sm) {
                    if let thinkingTime {
                        ThinkingTimeLabel(timing: thinkingTime, phase: processingStatus)
                    }
                    Spacer(minLength: DLSSpacing.sm)
                    if !message.text.isEmpty {
                        MessageActions(text: message.text, canEdit: canEdit, edit: edit)
                    }
                }
            }
            if isUser {
                Divider().overlay(theme.colors.border)
                if isCurrentReply, store.chatUsesAgent, !store.acp.toolActivities.isEmpty {
                    VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                        ForEach(store.acp.toolActivities) { activity in
                            ToolActivityRow(activity: activity)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUser ? "Your message" : "Assistant response")
    }

    private var isCurrentReply: Bool {
        isUser && store.sending && store.replyID != nil && store.lastUserMessageID == message.id
    }

    private var processingStatus: String? {
        guard isCurrentReply else { return nil }
        if store.stoppingReply { return "Stopping…" }
        if store.chatUsesAgent, let phase = store.acp.activityPhase { return phase }
        return thinkingTime?.isRunning == true ? "Thinking" : "Responding"
    }
}
