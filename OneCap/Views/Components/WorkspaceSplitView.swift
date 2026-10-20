import DLS
import SwiftUI

/// Keep the history and detail hosts stable when a request changes selection,
/// title, connection controls, and presentation state in the same update.
struct WorkspaceSplitView<Sidebar: View, Detail: View>: View {
    @Environment(AppStore.self) private var store
    @Binding var historyVisible: Bool
    var historyAvailable = true
    @State private var historyWidth: CGFloat = 210
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        NavigationStack {
            HSplitView {
                if historyAvailable && historyVisible {
                    sidebar()
                        .frame(minWidth: 200, idealWidth: 210, maxWidth: 340, maxHeight: .infinity)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DLSRadius.large))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { historyWidth = $0 }
                }
                detail()
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: historyAvailable && historyVisible ? 0 : DLSRadius.large,
                        topTrailingRadius: DLSRadius.large))
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
                        if store.chatUsesAgent { ChatAgentPicker() } else { ChatProviderPicker() }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if historyAvailable && historyVisible {
                    ToolbarItem(id: "history-column-inset", placement: .navigation) {
                        ToolbarColumnInset(boundary: ChatLayout.railWidth + historyWidth)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }
}
