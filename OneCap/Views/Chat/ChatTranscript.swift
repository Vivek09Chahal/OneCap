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
                            saveEdit: saveEdit, cancelEdit: cancelEdit
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
            .task(id: scrollTarget) {
                await Task.yield()
                guard !Task.isCancelled, let id = scrollTarget else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
            .onChange(of: messages.last?.text) { _, _ in
                // Coalesce streaming chunks and scroll outside the render/update pass.
                guard scrolling.pending == nil, let target = scrollTarget else { return }
                scrolling.pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(target, anchor: .bottom)
                    scrolling.pending = nil
                }
            }
            .onDisappear {
                scrolling.pending?.cancel()
                scrolling.pending = nil
            }
            .onChange(of: editingMessageID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

// Scheduling a scroll must not invalidate the transcript twice per streaming batch.
@MainActor private final class TranscriptScrollCoordinator {
    var pending: Task<Void, Never>?
}
