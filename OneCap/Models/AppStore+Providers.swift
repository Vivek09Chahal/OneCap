import Foundation

extension AppStore {
    func saveProvider(_ provider: Provider, key: String) async throws {
        _ = try ProviderClient.endpoint(provider.baseURL)
        guard !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !key.isEmpty
                else {
            throw AppFailure("Name, model ID, and API key are required.")
        }
        providers = try await repository.addProvider(provider, key: key)
        selectProvider(provider.id)
    }
    func removeProvider(_ provider: Provider) async {
        do {
            providers = try await repository.removeProvider(provider)
            if selectedProviderID == provider.id {
                resetChat()
                selectedProviderID = providers.first?.id
            }
        } catch { self.error = error.localizedDescription }
    }
}
