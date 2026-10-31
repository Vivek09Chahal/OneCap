import DLS
import SwiftUI

struct ProviderFormField<Control: View>: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    let hint: String?
    let control: Control
    
    init(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.hint = hint
        self.control = control()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            Text(title).dlsFont(.captionStrong)
            control
                .textFieldStyle(.plain)
                .dlsFont(.body)
                .padding(DLSSpacing.md)
                .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: DLSRadius.small).stroke(
                        theme.colors.border, lineWidth: DLSSize.border)
                }
            if let hint {
                Text(hint).dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
