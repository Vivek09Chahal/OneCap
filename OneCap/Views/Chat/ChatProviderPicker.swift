import SwiftUI

struct ChatProviderPicker: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ToolbarSelectionMenu(
            title: "Provider model",
            selectedTitle: store.providers.first(where: { $0.id == store.selectedProviderID })?.model ?? "Choose model",
            symbol: "network",
            selection: Binding(get: { store.selectedProviderID }, set: store.selectProvider)
        ) {
            Text("Choose model").tag(UUID?.none)
            ForEach(store.providers) { provider in
                Text("\(provider.name) · \(provider.model)").tag(Optional(provider.id))
            }
        }
        .disabled(store.sending || store.applyingFileUndo)
        .help("Choose a saved provider model")
    }
}
