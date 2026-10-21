import DLS
import SwiftUI

struct AgentCardHeader: View {
    @Environment(\.dlsTheme) private var theme
    let agent: Agent
    var displayedVersion: String? = nil
    
    var body: some View {
        HStack(spacing: DLSSpacing.md) {
            AgentIconView(agent: agent)
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                Text(agent.name).font(DLSTypography.heading).lineLimit(1).help(agent.name)
                Text("v\(displayedVersion ?? agent.version)").font(DLSTypography.monoCaption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DLSSpacing.sm)
            AgentLinksMenu(agent: agent)
        }
    }
}

private struct AgentLinksMenu: View {
    @Environment(\.dlsTheme) private var theme
    let agent: Agent
    
    var body: some View {
        let website = webURL(agent.website)
        let repository = webURL(agent.repository)
        if website != nil || repository != nil {
            Menu {
                if let website { Link("Website", destination: website) }
                if let repository { Link("Source repository", destination: repository) }
            } label: {
                Image(systemName: "ellipsis").font(DLSTypography.navigationIcon)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Links for \(agent.name)")
            .accessibilityLabel("Links for \(agent.name)")
        }
    }
    
    private func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
                else { return nil }
        return url
    }
}
