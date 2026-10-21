import DLS
import SwiftUI

/// Selects the ACP integration, independently of the model used in its session.
struct ChatAgentPicker: View {
    @Environment(\.displayScale) private var displayScale
    @State private var selectedImage: Image?
    @Environment(AppStore.self) private var store
    
    var body: some View {
        ToolbarSelectionMenu(
            title: "ACP agent",
            selectedTitle: store.selectedAgent?.name ?? "Choose agent",
            symbol: "cpu", selection: Binding(get: { store.selectedAgentID }, set: store.selectAgent),
            labelFont: DLSTypography.historyTitle,
            selectedImage: selectedImage, flexibleLabel: true
        ) {
            Text("Choose agent").tag(String?.none)
            ForEach(store.installed.filter { AgentCompatibility.unavailableReason(for: $0.id) == nil }) {
                Text($0.name).tag(Optional($0.id))
            }
        }
        .task(id: IconRequest(url: selectedIconURL, scale: displayScale)) {
            selectedImage = nil
            guard let url = selectedIconURL else { return }
            do {
                let image = try await AgentIconCache.image(
                    at: url, pointSize: DLSSize.iconSmall, scale: displayScale)
                try Task.checkCancellation()
                selectedImage = Image(nsImage: image).renderingMode(.template)
            } catch {
                // A missing or failed logo keeps the existing CPU symbol.
                if !Task.isCancelled { selectedImage = nil }
            }
        }
        .disabled(store.sending || store.acp.updatingConfiguration)
        .help("Choose an installed ACP agent. Its models are available in the composer below.")
    }
    private var selectedIconURL: URL? {
        store.agents.first(where: { $0.id == store.selectedAgentID })?.iconURL
    }

    private struct IconRequest: Hashable {
        let url: URL?
        let scale: CGFloat
    }
}
