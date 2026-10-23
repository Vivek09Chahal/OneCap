import DLS
import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var appearance: DLSAppearance
    @Environment(\.dlsTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Text("Theme").font(DLSTypography.heading)
            VStack(alignment: .leading, spacing: DLSSpacing.md) {
                HStack {
                    Text("App appearance")
                    Spacer()
                    Picker("App appearance", selection: $appearance) {
                        ForEach(DLSAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                Text("System follows your Mac’s light or dark appearance.")
                    .font(DLSTypography.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .cardSurface()
        }
    }
}
