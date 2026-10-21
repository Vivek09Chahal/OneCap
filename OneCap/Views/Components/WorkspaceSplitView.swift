import AppKit
import DLS
import SwiftUI

/// Keep the history and detail hosts stable when a request changes selection,
/// title, connection controls, and presentation state in the same update.
struct WorkspaceSplitView<Sidebar: View, Detail: View>: View {
    @Binding var historyVisible: Bool
    var historyAvailable = true
    var connectionSelected: () -> Void = {}
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @Environment(\.dlsTheme) private var theme
    @State private var historyFraction: CGFloat?
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = HistorySidebarSizing.width(in: geometry.size.width, fraction: historyFraction)
                HStack(spacing: DLSSpacing.none) {
                    if historyAvailable && historyVisible {
                        sidebar()
                            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: DLSRadius.large))
                        divider(width: width, availableWidth: geometry.size.width)
                            .frame(height: geometry.size.height)
                    }
                    detail()
                        .frame(minWidth: HistorySidebarSizing.detailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: historyAvailable && historyVisible ? 0 : DLSRadius.large,
                            topTrailingRadius: DLSRadius.large))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .animation(nil, value: geometry.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                if historyAvailable {
                    ToolbarItem(id: "toggle-history", placement: .navigation) {
                        ToolbarIconButton(title: "Toggle history sidebar", symbol: "sidebar.left") {
                            historyVisible.toggle()
                        }
                        .help(historyVisible ? "Hide chat history" : "Show chat history")
                        .accessibilityValue(historyVisible ? "Visible" : "Hidden")
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(id: "chat-selection", placement: .navigation) {
                        ChatConnectionPicker(didSelect: connectionSelected)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }

    private func divider(width: CGFloat, availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(width: HistorySidebarSizing.dividerWidth)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .background(HistoryDividerCursor())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = width }
                            setHistoryWidth((dragStartWidth ?? width) + value.translation.width, availableWidth: availableWidth)
                        }
                        .onEnded { _ in dragStartWidth = nil })
            }
            .accessibilityLabel("Resize history sidebar")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setHistoryWidth(width + 10, availableWidth: availableWidth)
                case .decrement: setHistoryWidth(width - 10, availableWidth: availableWidth)
                @unknown default: break
                }
            }
    }

    private func setHistoryWidth(_ width: CGFloat, availableWidth: CGFloat) {
        guard availableWidth > 0 else { return }
        historyFraction = HistorySidebarSizing.clampedWidth(width, in: availableWidth) / availableWidth
    }
}

private struct HistoryDividerCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleRect, cursor: .resizeLeftRight)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }
    }
}
