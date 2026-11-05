import DLS
import SwiftUI

struct ProviderChatModePicker: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ComposerOptionsButton(
            enabled: !store.stoppingReply && !store.connecting,
            label: {
                ComposerControlLabel {
                    HStack(spacing: DLSSpacing.xs) {
                        Text(store.chatSession.providerMode.title)
                        Image(systemName: "chevron.up").dlsFont(.footnote)
                    }
                }
            },
            content: { dismiss in
                ComposerOptionsList(rowCount: ProviderChatMode.allCases.count, headingCount: 0) {
                    ForEach(ProviderChatMode.allCases, id: \.self) { mode in
                        ComposerOptionRow(title: mode.title, selected: store.chatSession.providerMode == mode) {
                            store.selectProviderMode(mode)
                            dismiss()
                        }
                    }
                }
            }
        )
        .accessibilityLabel("Response mode: \(store.chatSession.providerMode.title)")
        .help("Ask questions, write code, or plan changes")
    }
}
