import AppKit
import DLS
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.dlsTheme) private var theme

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: DLSSpacing.lg) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                Text("OneCap")
                    .font(DLSTypography.heading)
                Text("Version \(version)")
                    .font(DLSTypography.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
