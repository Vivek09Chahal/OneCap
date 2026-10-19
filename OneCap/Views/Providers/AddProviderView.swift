import DLS
import SwiftUI

struct AddProviderView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preset: ProviderFormPreset = .deepSeek
    @State private var name = ProviderFormPreset.deepSeek.name
    @State private var baseURL = ProviderFormPreset.deepSeek.baseURL
    @State private var model = ProviderFormPreset.deepSeek.model
    @State private var key = ""
    @State private var error: String?
    @State private var saving = false
    
    private var canSave: Bool {
        [name, baseURL, model, key].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xxl) {
            ProviderFormHeader()
            Picker("Provider preset", selection: $preset) {
                ForEach(ProviderFormPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().disabled(saving)
            .onChange(of: preset) { _, value in
                name = value.name
                baseURL = value.baseURL
                model = value.model
                key = ""
                error = nil
            }
            ProviderConnectionFields(name: $name, baseURL: $baseURL, model: $model, key: $key)
                .disabled(saving)
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(DLSTypography.caption).foregroundStyle(theme.colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(theme.colors.border)
            HStack(spacing: DLSSpacing.md) {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(
                    saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(saving ? "Saving…" : "Add provider", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || !canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DLSSpacing.xxxl)
        .frame(width: ProvidersLayout.formWidth)
        .background(theme.colors.background)
        .interactiveDismissDisabled(saving)
        .onDisappear { key = "" }
    }
    
    private func save() {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await store.saveProvider(
                    .init(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: model.trimmingCharacters(in: .whitespacesAndNewlines)),
                    key: key.trimmingCharacters(in: .whitespacesAndNewlines))
                key = ""
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ProviderFormHeader: View {
    @Environment(\.dlsTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.md) {
            Image(systemName: "key.horizontal").font(DLSTypography.brandTitle)
                .foregroundStyle(theme.colors.accent)
                .frame(width: DLSSize.avatar, height: DLSSize.avatar)
                .background(theme.colors.accentSubtle, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                Text("Add provider").font(DLSTypography.sectionTitle)
                Text("Connect an OpenAI-compatible API with your own key.")
                    .font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
