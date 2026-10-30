import DLS
import SwiftUI

/// Model selection stays independent of the agent's other session settings.
struct ChatModelPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    
    var body: some View {
        let options = store.acp.sessionOptions.filter(\.isModelSelector)
        ComposerOptionsButton(
            enabled: !store.sending && !store.connecting && !store.acp.updatingConfiguration
            && (store.chatUsesAgent ? !options.isEmpty : !store.providers.isEmpty),
            label: {
                ComposerControlLabel {
                    HStack(spacing: DLSSpacing.xs) {
                        Text(modelName).foregroundStyle(theme.colors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down").font(DLSTypography.footnote)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            },
            content: { dismiss in
                if store.chatUsesAgent {
                    SessionOptionsList(options: options, dismiss: dismiss)
                } else {
                    ComposerOptionsList(rowCount: store.providers.count, headingCount: 1) {
                        Text("Provider model").font(DLSTypography.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, DLSSpacing.sm)
                        ForEach(store.providers) { provider in
                            ComposerOptionRow(
                                title: "\(provider.name) · \(provider.model)",
                                selected: provider.id == store.selectedProviderID
                            ) {
                                dismiss()
                                store.selectProvider(provider.id)
                            }
                        }
                    }
                }
            }
        )
        .frame(maxWidth: 300, alignment: .trailing)
        .accessibilityLabel("Model options")
        .help(
            store.chatUsesAgent
            ? "Models provided by the selected agent harness"
            : "Choose a saved provider model")
    }
    
    private var modelName: String {
        if store.chatUsesAgent {
            return store.acp.sessionOptions.first(where: \.isModelSelector)?.selectedName
            ?? "Agent default"
        }
        return store.selectedProvider?.model
        ?? "Choose model"
    }
}
