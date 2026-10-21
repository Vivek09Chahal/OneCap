import SwiftUI

struct RegistryHeader: View {
    let installedCount: Int
    var body: some View {
        ManagementPageHeader(
            title: "Agent Harnesses", subtitle: "Your coding agents, all in one workspace.",
            summary: installedCount > 0 ? "\(installedCount) installed" : nil)
    }
}
