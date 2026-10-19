import DLS
import Kingfisher
import SwiftUI

/// Resolve logos from the current registry at runtime; Kingfisher owns fetching and caching.
struct AgentIconView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    let agent: Agent

    var body: some View {
        KFImage(agent.iconURL)
            .targetCache(AgentIconCache.images)
            .originalCache(AgentIconCache.images)
            .setProcessor(AgentIconProcessor(pointSize: DLSSize.iconLarge, scale: displayScale))
            .processingQueue(.dispatch(AgentIconCache.processing))
            .cacheOriginalImage()
            .memoryCacheExpiration(.days(7))
            .diskCacheExpiration(.days(30))
            .cancelOnDisappear(true)
            .fade(duration: 0.15)
            .placeholder {
                Image(systemName: "cpu")
                    .font(DLSTypography.featureIcon)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: DLSSize.iconLarge, height: DLSSize.iconLarge)
            .frame(width: DLSSize.avatar, height: DLSSize.avatar)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
            .accessibilityHidden(true)
    }
}
