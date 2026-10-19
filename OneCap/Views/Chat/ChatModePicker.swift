import DLS
import SwiftUI

/// Agent, Plan, Ask, and other advertised modes are independent of model selection.
struct ChatModePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    
    var body: some View {
        let modes = store.acp.sessionOptions.filter(\.isModeSelector)
        if let mode = modes.first {
            ComposerOptionsButton(
                enabled: !store.sending && !store.connecting && !store.acp.updatingConfiguration,
                label: {
                    HStack(spacing: DLSSpacing.xs) {
                        Image(systemName: "slider.horizontal.3")
                        Text(mode.selectedName).lineLimit(1)
                        Image(systemName: "chevron.up")
                    }
                    .font(DLSTypography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                },
                content: { dismiss in SessionOptionsList(options: modes, dismiss: dismiss) }
            )
            .accessibilityLabel("Agent mode: \(mode.selectedName)")
            .help("Choose the agent's mode, such as Plan or Ask")
        }
    }
}
