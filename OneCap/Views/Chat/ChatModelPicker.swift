import DLS
import SwiftUI

/// Models and reasoning supplied by the selected agent; mode has its own control.
struct ChatModelPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    
    var body: some View {
        let options = store.acp.sessionOptions.filter { !$0.isModeSelector }
        ComposerOptionsButton(
            enabled: !store.sending && !store.connecting && !store.acp.updatingConfiguration
            && (store.chatUsesAgent ? !options.isEmpty : !store.providers.isEmpty),
            label: {
                HStack(spacing: DLSSpacing.xs) {
                    Text(
                        "\(Text(modelName).foregroundStyle(theme.colors.textPrimary))\(Text(reasoningName).foregroundStyle(theme.colors.textSecondary))"
                    )
                    Image(systemName: "chevron.up").foregroundStyle(theme.colors.textSecondary)
                }
                .font(DLSTypography.caption)
                .lineLimit(1)
                .truncationMode(.middle)
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
            ? "Models and reasoning provided by the selected ACP agent"
            : "Choose a saved provider model")
    }
    
    private var reasoningName: String {
        guard store.chatUsesAgent,
              let reasoning = store.acp.sessionOptions.first(where: { $0.category == "thought_level" })
                else { return "" }
        return " · " + reasoning.selectedName
    }
    
    private var modelName: String {
        if store.chatUsesAgent {
            return store.acp.sessionOptions.first(where: { $0.category == "model" })?.selectedName
            ?? "Agent default"
        }
        return store.providers.first(where: { $0.id == store.selectedProviderID })?.model
        ?? "Choose model"
    }
}
