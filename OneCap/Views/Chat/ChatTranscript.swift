import AppKit
import Combine
import DLS
import SwiftUI

struct ChatTranscript: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.chatAppearance) private var chatAppearance
    @Environment(\.dlsReduceMotion) private var reduceMotion
    let messages: [ChatMessage]
    let editableMessageID: UUID?
    let editingMessageID: UUID?
    @Binding var editedText: String
    let canResend: Bool
    let beginEdit: (UUID) -> Void
    let saveEdit: () -> Void
    let cancelEdit: () -> Void
    var currentReplyUserID: UUID? = nil
    var bottomInset: CGFloat = 0
    @State private var showsScrollToLatest = false
    @State private var scrolling = TranscriptScrollCoordinator()
    
    private var scrollTarget: UUID? {
        messages.last(where: { $0.role == "user" || !$0.text.isEmpty })?.id
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: chatAppearance.spacing(DLSSpacing.md)) {
                    ForEach(ChatTranscriptEntry.make(from: messages)) { entry in
                        ChatMessageRow(
                            message: entry.message, thinkingTime: entry.thinkingTime,
                            canEdit: editableMessageID == entry.id,
                            isEditing: editingMessageID == entry.id, editedText: $editedText,
                            canResend: canResend, edit: { beginEdit(entry.id) },
                            saveEdit: saveEdit, cancelEdit: cancelEdit,
                            isCurrentReply: currentReplyUserID == entry.id
                        )
                        .padding(.bottom, entry.message.role == "user" ? DLSSpacing.none : chatAppearance.spacing(DLSSpacing.xl))
                        .id(entry.id)
                    }
                }
                .chatColumn()
                .padding(.vertical, DLSSpacing.xxxl)
                .id(TranscriptScrollAnchor.bottom)
                .background {
                    TranscriptScrollObserver { previous, current in
                        applyScrollMetrics(previous: previous, current: current)
                    }
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .onScrollPhaseChange { _, phase in
                scrolling.userIsScrolling = phase != .idle
                if scrolling.userIsScrolling {
                    // Wheel, trackpad, and scrollbar input take priority over streamed replies.
                    scrolling.followsLatest = false
                    scrolling.pending?.cancel()
                    scrolling.pending = nil
                    scrolling.target = nil
                } else if phase == .idle {
                    scrolling.followsLatest = scrolling.atBottom
                }
            }
            // Native initial anchoring opens saved chats at the bottom. Only
            // subsequent messages need a programmatic scroll; scrolling again
            // on mount makes the lazy stack lay out the saved transcript twice.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                scheduleScroll(to: target, using: proxy)
            }
            .onReceive(Just(messages.last?.text)) { text in
                // Coalesce streaming chunks and scroll outside the render/update pass.
                // A stream can deliver several values during one SwiftUI frame;
                // onChange's per-frame action limit is inappropriate for this input.
                let changed = scrolling.hasReceivedText && scrolling.lastText != text
                scrolling.hasReceivedText = true
                scrolling.lastText = text
                guard changed else { return }
                guard let target = scrollTarget else { return }
                scheduleScroll(to: target, using: proxy)
            }
            .onDisappear {
                scrolling.pending?.cancel()
                scrolling.pending = nil
                scrolling.target = nil
                scrolling.hasReceivedText = false
                scrolling.lastText = nil
                scrolling.followsLatest = true
                scrolling.nearBottom = true
                scrolling.atBottom = true
                scrolling.userIsScrolling = false
            }
            .onChange(of: editingMessageID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if showsScrollToLatest {
                    Button {
                        scrolling.pending?.cancel()
                        scrolling.pending = nil
                        scrolling.target = nil
                        scrolling.followsLatest = true
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                            proxy.scrollTo(TranscriptScrollAnchor.bottom, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(theme.colors.surface, in: Circle())
                            .overlay(Circle().strokeBorder(theme.colors.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll to latest message")
                    .accessibilityLabel("Scroll to latest message")
                    .padding(.bottom, bottomInset + 48)
                }
            }
        }
    }

    private func scheduleScroll(to target: UUID, using proxy: ScrollViewProxy) {
        guard scrolling.followsLatest, !scrolling.userIsScrolling else { return }
        scrolling.target = target
        guard scrolling.pending == nil else { return }
        scrolling.pending = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            guard !Task.isCancelled, scrolling.followsLatest, !scrolling.userIsScrolling,
                  scrolling.target != nil else { return }
            proxy.scrollTo(TranscriptScrollAnchor.bottom, anchor: .bottom)
            scrolling.pending = nil
            scrolling.target = nil
        }
    }

    private func applyScrollMetrics(previous: TranscriptScrollMetrics, current: TranscriptScrollMetrics) {
        scrolling.nearBottom = current.nearBottom
        scrolling.atBottom = current.atBottom
        let showLatest = !current.nearBottom
        if showLatest != showsScrollToLatest { showsScrollToLatest = showLatest }
        if current.offset < previous.offset - 1 {
            // Also covers keyboard and scrollbar movement without a wheel phase.
            scrolling.followsLatest = false
            scrolling.pending?.cancel()
            scrolling.pending = nil
            scrolling.target = nil
        }
        // Resume only after deliberate downward movement reaches the bottom.
        // Streamed layout changes near the bottom must not reclaim scrolling.
        if current.atBottom, current.offset > previous.offset, !scrolling.userIsScrolling {
            scrolling.followsLatest = true
        }
    }
}

// ScrollPosition observes geometry internally and can publish repeatedly while
// streamed text changes the lazy stack. Use the reader's stable content anchor.
private enum TranscriptScrollAnchor: Hashable {
    case bottom
}

// Scheduling a scroll must not invalidate the transcript twice per streaming batch.
@MainActor private final class TranscriptScrollCoordinator {
    var followsLatest = true
    var nearBottom = true
    var atBottom = true
    var userIsScrolling = false
    var pending: Task<Void, Never>?
    var target: UUID?
    var hasReceivedText = false
    var lastText: String?
}

private struct TranscriptScrollMetrics: Equatable {
    let offset: CGFloat
    let nearBottom: Bool
    let atBottom: Bool
}

// Observe native bounds outside SwiftUI's scroll-geometry update cycle. Lazy
// transcript layout and programmatic scrolling can both change bounds in a frame.
private struct TranscriptScrollObserver: NSViewRepresentable {
    var onChange: (TranscriptScrollMetrics, TranscriptScrollMetrics) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.detach()
    }

    final class ObserverView: NSView {
        var onChange: ((TranscriptScrollMetrics, TranscriptScrollMetrics) -> Void)?
        private weak var scrollView: NSScrollView?
        private var pending: Task<Void, Never>?
        private var previous: TranscriptScrollMetrics?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil, let scroll = enclosingScrollView else { return }
            scrollView = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            if let document = scroll.documentView {
                document.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                    name: NSView.frameDidChangeNotification, object: document)
            }
            boundsChanged()
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            pending?.cancel()
            pending = nil
            scrollView = nil
            previous = nil
        }

        @objc private func boundsChanged() {
            guard pending == nil else { return }
            pending = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                self.pending = nil
                guard let scroll = self.scrollView, let document = scroll.documentView else { return }
                let visible = scroll.contentView.documentVisibleRect
                let insets = scroll.contentInsets
                let distance = document.isFlipped
                    ? document.bounds.maxY + insets.bottom - visible.maxY
                    : visible.minY - document.bounds.minY + insets.bottom
                let offset = document.isFlipped ? visible.minY : -visible.maxY
                let current = TranscriptScrollMetrics(offset: offset,
                    nearBottom: distance <= 32, atBottom: distance <= 1)
                let old = self.previous
                self.previous = current
                if old != current { self.onChange?(old ?? current, current) }
            }
        }
    }
}
