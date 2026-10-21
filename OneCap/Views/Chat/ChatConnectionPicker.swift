import DLS
import SwiftUI

/// Choose the connection type from the window toolbar.
struct ChatConnectionPicker: View {
    @Environment(AppStore.self) private var store
    let didSelect: () -> Void

    var body: some View {
        ToolbarSelectionMenu(
            title: "Connection", selectedTitle: store.chatUsesAgent ? "Agent harness" : "Provider chat",
            symbol: store.chatUsesAgent ? "terminal" : "network",
            selection: Binding(get: { store.chatUsesAgent }, set: { selected in
                store.selectChatMode(selected)
                didSelect()
            })
        ) {
            Text("Provider chat").tag(false)
            Text("Agent harness").tag(true)
        }
        .disabled(store.sending || store.applyingFileUndo)
        .help("Choose provider chat or an agent harness")
    }
}
