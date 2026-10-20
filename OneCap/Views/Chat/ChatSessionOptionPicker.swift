import DLS
import SwiftUI

/// One independent control per option, in the order advertised by the agent.
struct ChatSessionOptionPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let option: ACPSessionOption

    var body: some View {
        Group {
            if let values = option.toggleValues {
                ComposerControlLabel {
                    Toggle(option.name, isOn: Binding(
                        get: { option.currentValue == values.on },
                        set: { enabled in
                            Task { await store.changeSessionOption(option.id, value: enabled ? values.on : values.off) }
                        }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(theme.colors.accent)
                }
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!enabled)
            } else {
                picker
            }
        }
        .accessibilityLabel("\(option.name): \(option.selectedName)")
        .help(option.detail ?? option.name)
    }

    private var enabled: Bool {
        store.acp.sessionReady && !store.sending && !store.connecting
            && !store.acp.updatingConfiguration && !option.choices.isEmpty
    }

    private var picker: some View {
        ComposerOptionsButton(
            enabled: enabled,
            label: {
                ComposerControlLabel {
                    HStack(spacing: DLSSpacing.xs) {
                        Text(option.selectedName).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.up").font(DLSTypography.footnote)
                    }
                }
                .frame(maxWidth: 190, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            },
            content: { dismiss in SessionOptionsList(options: [option], dismiss: dismiss) }
        )
    }
}
