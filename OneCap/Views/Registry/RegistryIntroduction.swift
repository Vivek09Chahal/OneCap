import DLS
import SwiftUI

struct RegistryIntroduction: View {
    @Environment(\.dlsTheme) private var theme
    @State private var expanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: DLSSpacing.md) {
                Text(
                    "Edth manages agent downloads and Node.js. Each agent manages its own sign-in, model access, and billing."
                )
                Text("Installing an agent runs third-party software, including any package setup scripts.")
                Text("Edth connects directly to official harness interfaces where supported, and uses ACP for other agents.")
                Link(
                    "Learn about the Agent Client Protocol ↗",
                    destination: URL(string: "https://agentclientprotocol.com")!)
            }
            .dlsFont(.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DLSSpacing.md)
        } label: {
            Label("About agent installation", systemImage: "info.circle")
                .dlsFont(.callout)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(DLSSpacing.lg)
        .background(theme.colors.sidebar, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
    }
}
