import DLS
import SwiftUI

/// Keep the history and detail hosts stable when a request changes selection,
/// title, connection controls, and presentation state in the same update.
struct WorkspaceSplitView<Sidebar: View, Detail: View>: View {
    @Binding var historyVisible: Bool
    @State private var historyWidth: CGFloat = 260
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        NavigationStack {
            HSplitView {
                if historyVisible {
                    sidebar()
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340, maxHeight: .infinity)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DLSRadius.large))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { historyWidth = $0 }
                }
                detail()
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(UnevenRoundedRectangle(topTrailingRadius: DLSRadius.large))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(id: "toggle-history", placement: .navigation) {
                    ToolbarIconButton(title: "Toggle history sidebar", symbol: "sidebar.left") {
                        historyVisible.toggle()
                    }
                    .help(historyVisible ? "Hide chat history" : "Show chat history")
                    .accessibilityValue(historyVisible ? "Visible" : "Hidden")
                }
                if historyVisible {
                    ToolbarItem(id: "history-column-inset", placement: .navigation) {
                        ToolbarColumnInset(boundary: ChatLayout.railWidth + historyWidth)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }
}
