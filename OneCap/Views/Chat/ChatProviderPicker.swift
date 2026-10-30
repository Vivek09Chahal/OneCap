import DLS
import SwiftUI

struct ChatProviderPicker: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        ToolbarSelectionMenu(
            title: "Provider model",
            selectedTitle: store.selectedProvider?.model ?? "Choose model",
            symbol: "network",
            selection: Binding(get: { store.selectedProviderID }, set: store.selectProvider),
            labelFont: DLSTypography.historyProviderTitle, flexibleLabel: true, unifiedForeground: true,
            labelColor: theme.colors.textPrimary
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
