import DLS
import SwiftUI

struct ChatConnectionNotice: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            Label(message, systemImage: "exclamationmark.circle")
            if store.acp.authenticationRequired && !store.acp.authMethods.isEmpty {
                ChatAuthenticationMenu(title: "Sign in again")
            } else if store.authenticationNeedsRetry && store.acp.sessionReady {
                Button("Retry last message", systemImage: "arrow.clockwise") {
                    store.retryAuthenticatedMessage()
                }
                .disabled(store.sending || store.connecting)
            }
        }
            .font(DLSTypography.callout)
            .foregroundStyle(theme.colors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DLSSpacing.md)
            .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
    }
}
