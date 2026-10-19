import DLS
import SwiftUI

struct ProvidersEmptyState: View {
    let searching: Bool
    let add: () -> Void
    let clear: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label(
                searching ? "No matching providers" : "Add your first provider",
                systemImage: searching ? "magnifyingglass" : "key.horizontal")
        } description: {
            Text(
                searching
                ? "Search by provider name, model, or API endpoint."
                : "Connect an OpenAI-compatible API with your own key to start chatting.")
        } actions: {
            if searching {
                Button("Clear search", action: clear)
            } else {
                Button("Add provider", systemImage: "plus", action: add).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}
