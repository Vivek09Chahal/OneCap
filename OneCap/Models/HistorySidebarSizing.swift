import Foundation

enum HistorySidebarSizing {
    static let defaultWidth: CGFloat = 202
    // The default 1,180-point workspace window minus its 46-point navigation rail.
    static let referenceWidth: CGFloat = 1134
    static let minimumWidth: CGFloat = 196
    static let maximumWidth: CGFloat = 340
    static let detailMinimumWidth: CGFloat = 400
    static let dividerWidth: CGFloat = 1

    static func width(in availableWidth: CGFloat, fraction: CGFloat?) -> CGFloat {
        let scale = fraction ?? (defaultWidth / referenceWidth)
        return clampedWidth(scale * availableWidth, in: availableWidth)
    }

    static func clampedWidth(_ width: CGFloat, in availableWidth: CGFloat) -> CGFloat {
        let maximum = min(maximumWidth, max(0, availableWidth - detailMinimumWidth - dividerWidth))
        let minimum = min(minimumWidth, maximum)
        return min(maximum, max(minimum, width))
    }
}
