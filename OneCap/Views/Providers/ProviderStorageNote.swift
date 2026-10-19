import DLS
import SwiftUI

struct ProviderStorageNote: View {
    @Environment(\.dlsTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.md) {
            Image(systemName: "lock.shield").font(DLSTypography.navigationIcon)
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                Text("Your keys stay in macOS Keychain.").font(DLSTypography.captionStrong)
                Text("Providers power direct chat. ACP agents manage their own sign-in and model access.")
                    .font(DLSTypography.caption)
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DLSSpacing.lg)
        .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
    }
}
