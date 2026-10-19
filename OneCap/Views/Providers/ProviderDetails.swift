import DLS
import SwiftUI

struct ProviderDetails: View {
    @Environment(\.dlsTheme) private var theme
    let provider: Provider
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DLSSpacing.lg, verticalSpacing: DLSSpacing.sm) {
            detail("Model", value: provider.model)
            detail("Endpoint", value: provider.baseURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func detail(_ title: String, value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title).font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
            Text(value).font(DLSTypography.monoCaption).textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle).help(value)
        }
    }
}
