import SwiftUI

/// Selects the ACP integration, independently of the model used in its session.
struct ChatAgentPicker: View {
    @Environment(AppStore.self) private var store
    
    var body: some View {
        ToolbarSelectionMenu(
            title: "ACP agent",
            selectedTitle: store.installed.first(where: { $0.id == store.selectedAgentID })?.name ?? "Choose agent",
            symbol: "cpu", selection: Binding(get: { store.selectedAgentID }, set: store.selectAgent)
        ) {
            Text("Choose agent").tag(String?.none)
            ForEach(store.installed.filter { AgentCompatibility.unavailableReason(for: $0.id) == nil }) {
                Text($0.name).tag(Optional($0.id))
            }
        }
        .disabled(store.sending || store.acp.updatingConfiguration)
        .help("Choose an installed ACP agent. Its models are available in the composer below.")
    }
}
