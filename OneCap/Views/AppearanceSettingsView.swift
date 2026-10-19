import DLS
import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var appearance: DLSAppearance
    @Environment(\.dlsTheme) private var theme
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(DLSAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Text("System follows your Mac’s light or dark appearance.")
                .font(DLSTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .formStyle(.grouped)
        .padding(DLSSpacing.xxl)
        .frame(width: 400)
    }
}
