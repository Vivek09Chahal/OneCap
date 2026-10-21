import DLS
import SwiftUI

struct RegistryEmptyState: View {
    let searching: Bool
    let catalogEmpty: Bool
    let reset: () -> Void
    let refresh: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: searching ? "magnifyingglass" : "square.stack.3d.up")
        } description: {
            Text(description)
        } actions: {
            if catalogEmpty {
                Button("Refresh harnesses", action: refresh)
            } else if searching {
                Button("Clear search", action: reset)
            }
        }
        .frame(maxWidth: .infinity, minHeight: RegistryLayout.cardHeight)
    }
    
    private var title: String {
        if searching { return "No matching agents" }
        if catalogEmpty { return "No agent harnesses available" }
        return "No supported agents to show"
    }
    
    private var description: String {
        if searching { return "Try a different agent name or keyword." }
        if catalogEmpty { return "Refresh to load the latest agent catalog." }
        return "Only distributions supported by OneCap on this Mac are listed here."
    }
}
