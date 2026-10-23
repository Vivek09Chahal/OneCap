import DLS
import SwiftUI

struct ChatTranscript: View {
    let messages: [ChatMessage]
    let editableMessageID: UUID?
    let editingMessageID: UUID?
    @Binding var editedText: String
    let canResend: Bool
    let beginEdit: (UUID) -> Void
    let saveEdit: () -> Void
    let cancelEdit: () -> Void
    var currentReplyUserID: UUID? = nil
    @State private var scrolling = TranscriptScrollCoordinator()
    
    private var scrollTarget: UUID? {
        messages.last(where: { $0.role == "user" || !$0.text.isEmpty })?.id
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DLSSpacing.md) {
                    ForEach(ChatTranscriptEntry.make(from: messages)) { entry in
                        ChatMessageRow(
                            message: entry.message, thinkingTime: entry.thinkingTime,
                            canEdit: editableMessageID == entry.id,
                            isEditing: editingMessageID == entry.id, editedText: $editedText,
                            canResend: canResend, edit: { beginEdit(entry.id) },
                            saveEdit: saveEdit, cancelEdit: cancelEdit,
                            isCurrentReply: currentReplyUserID == entry.id
                        )
                        .padding(.bottom, entry.message.role == "user" ? DLSSpacing.none : DLSSpacing.xl)
                        .id(entry.id)
                    }
                }
                .chatColumn()
                .padding(.vertical, DLSSpacing.xxxl)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // Native initial anchoring opens saved chats at the bottom. Only
            // subsequent messages need a programmatic scroll; scrolling again
            // on mount makes the lazy stack lay out the saved transcript twice.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                scheduleScroll(to: target, using: proxy)
            }
            .onChange(of: messages.last?.text) { _, _ in
                // Coalesce streaming chunks and scroll outside the render/update pass.
                guard let target = scrollTarget else { return }
                scheduleScroll(to: target, using: proxy)
            }
            .onDisappear {
                scrolling.pending?.cancel()
                scrolling.pending = nil
                scrolling.target = nil
            }
            .onChange(of: editingMessageID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func scheduleScroll(to target: UUID, using proxy: ScrollViewProxy) {
        scrolling.target = target
        guard scrolling.pending == nil else { return }
        scrolling.pending = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            guard !Task.isCancelled, let latestTarget = scrolling.target else { return }
            proxy.scrollTo(latestTarget, anchor: .bottom)
            scrolling.pending = nil
            scrolling.target = nil
        }
    }
}

// Scheduling a scroll must not invalidate the transcript twice per streaming batch.
@MainActor private final class TranscriptScrollCoordinator {
    var pending: Task<Void, Never>?
    var target: UUID?
}
