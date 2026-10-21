import DLS
import SwiftUI

/// A new conversation or agent selection restarts the notification's lifetime.
struct AgentSelectionToast: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let agentName: String?
    let conversationID: UUID
    var iconURL: URL?
    @State private var visible = false
    @State private var agentIcon: Image?

    private struct Selection: Equatable {
        let agentName: String?
        let conversationID: UUID
    }

    private struct IconRequest: Equatable {
        let url: URL?
        let scale: CGFloat
    }

    var body: some View {
        ZStack {
            if visible, let agentName {
                HStack(spacing: DLSSpacing.sm) {
                    if let agentIcon {
                        agentIcon
                            .resizable()
                            .scaledToFit()
                            .frame(width: DLSSize.iconSmall, height: DLSSize.iconSmall)
                            .accessibilityHidden(true)
                    }
                    Text("Selected agent: \(agentName)")
                        .font(DLSTypography.callout)
                        .lineLimit(2)
                }
                .foregroundStyle(theme.colors.accent)
                .padding(.horizontal, DLSSpacing.lg)
                .padding(.vertical, DLSSpacing.md)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
                .shadow(color: .black.opacity(0.12), radius: DLSSpacing.md, y: DLSSpacing.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visible)
        .task(id: IconRequest(url: iconURL, scale: displayScale)) {
            agentIcon = nil
            guard let iconURL else { return }
            do {
                let image = try await AgentIconCache.image(
                    at: iconURL, pointSize: DLSSize.iconSmall, scale: displayScale)
                try Task.checkCancellation()
                agentIcon = Image(nsImage: image).renderingMode(.template)
            } catch {
                // Keep the agent's name visible when its logo is unavailable.
                if !Task.isCancelled { agentIcon = nil }
            }
        }
        .task(id: Selection(agentName: agentName, conversationID: conversationID)) {
            visible = agentName != nil
            guard visible else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                try Task.checkCancellation()
                visible = false
            } catch { /* A newer selection owns the toast's lifetime. */ }
        }
    }
}
