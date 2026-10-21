import DLS
import SwiftUI

struct RegistryToolbar: ToolbarContent {
    let loading: Bool
    let refresh: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton(title: "Refresh harnesses", symbol: "arrow.clockwise", action: refresh)
                .disabled(loading)
                .help("Refresh the agent harness catalog")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
