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

    var body: some View {
        NavigationStack {
            HSplitView {
                if historyAvailable && historyVisible {
                    sidebar()
                        .frame(minWidth: 196, idealWidth: 206, maxWidth: 340, maxHeight: .infinity)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DLSRadius.large))
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
                        ChatConnectionPicker(didSelect: connectionSelected)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }
}
