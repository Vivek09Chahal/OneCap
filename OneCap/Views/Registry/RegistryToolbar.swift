import DLS
import SwiftUI

struct RegistryToolbar: ToolbarContent {
    let loading: Bool
    let refresh: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton(title: "Refresh registry", symbol: "arrow.clockwise", action: refresh)
                .disabled(loading)
                .help("Refresh the ACP agent catalog")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
