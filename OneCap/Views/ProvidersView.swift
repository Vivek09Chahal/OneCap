import DLS
import SwiftUI

struct ProvidersView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    let openChat: () -> Void
    @State private var adding = false
    @State private var search = ""
    
    private var filtered: [Provider] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.providers.filter {
            query.isEmpty || "\($0.name) \($0.model) \($0.baseURL)".localizedStandardContains(query)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DLSSpacing.xxl) {
                ManagementPageHeader(
                    title: "Providers", subtitle: "Connect your own API keys and choose the models you use.",
                    summary: store.providers.isEmpty ? nil : "\(store.providers.count) configured",
                    summarySymbol: "key.horizontal")
                if store.providers.isEmpty {
                    ProvidersEmptyState(searching: false, add: { adding = true }, clear: { search = "" })
                } else if filtered.isEmpty {
                    ProvidersEmptyState(searching: true, add: { adding = true }, clear: { search = "" })
                } else {
                    ManagementSectionHeader(title: "Your providers", count: filtered.count)
                    ForEach(filtered) { provider in
                        ProviderCard(
                            provider: provider,
                            selected: !store.chatUsesAgent && store.selectedProviderID == provider.id,
                            busy: store.sending,
                            openChat: { startChat(with: provider) },
                            remove: { await store.removeProvider(provider) })
                    }
                }
                ProviderStorageNote()
            }
            .frame(maxWidth: ProvidersLayout.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(DLSSpacing.xxxl)
        }
        .background(theme.colors.background)
        .navigationTitle("Providers")
        .searchable(text: $search, placement: .toolbar, prompt: "Search providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarIconButton(title: "Add provider", symbol: "plus") { adding = true }
                    .help("Connect a provider using your own API key")
            }
        }
        .sheet(isPresented: $adding) { AddProviderView() }
    }
    
    private func startChat(with provider: Provider) {
        guard !store.sending else { return }
        store.selectChatMode(false)
        store.selectProvider(provider.id)
        openChat()
    }
}
