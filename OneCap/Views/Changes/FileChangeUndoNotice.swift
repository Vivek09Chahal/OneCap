import DLS
import SwiftUI

struct FileChangeUndoNotice: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.colors.warning)
            Text(message).font(DLSTypography.caption).textSelection(.enabled)
            Spacer(minLength: DLSSpacing.sm)
            Button("Dismiss", systemImage: "xmark") { store.fileChangeError = nil }
                .labelStyle(.iconOnly).buttonStyle(.plain)
        }
        .foregroundStyle(theme.colors.textSecondary)
    }
}
