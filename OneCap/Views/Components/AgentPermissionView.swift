import DLS
import SwiftUI

struct AgentPermissionView: View {
    @Environment(\.dlsTheme) private var theme
    let request: PermissionRequest
    let resolve: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xl) {
            Label("Agent permission", systemImage: "hand.raised").font(DLSTypography.sectionTitle)
            Text(request.title).textSelection(.enabled)
            Text("Review this action before allowing the agent to continue.").foregroundStyle(
                theme.colors.textSecondary)
            ForEach(request.options) { option in
                Button(option.name) { resolve(option.id) }
            }
            Button("Cancel request", role: .cancel) { resolve(nil) }
        }.padding(DLSSpacing.xxxl).frame(width: 460).interactiveDismissDisabled()
    }
}
