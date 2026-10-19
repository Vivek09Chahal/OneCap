import DLS
import SwiftUI

/// Choose the connection type from the history heading.
struct ChatConnectionPicker: View {
    @Environment(AppStore.self) private var store
    let didSelect: () -> Void

    var body: some View {
        ToolbarSelectionMenu(
            title: "Connection", selectedTitle: store.chatUsesAgent ? "ACP agent" : "Provider chat",
            symbol: store.chatUsesAgent ? "terminal" : "network",
            selection: Binding(get: { store.chatUsesAgent }, set: { selected in
                store.selectChatMode(selected)
                didSelect()
            }), labelFont: DLSTypography.historyTitle
        ) {
            Text("Provider chat").tag(false)
            Text("ACP agent").tag(true)
        }
        .disabled(store.sending || store.applyingFileUndo)
        .help("Choose provider chat or an ACP agent")
    }
}
