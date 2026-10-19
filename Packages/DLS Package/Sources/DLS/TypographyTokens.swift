import SwiftUI

/// Use semantic text styles for content so system accessibility sizing can participate.
public enum DLSTypography {
    /// Shared point size for the AppKit terminal emulator.
    public static let terminalPointSize: CGFloat = 13
    public static let catalogTitle = Font.system(.largeTitle).weight(.semibold)
    public static let pageTitle = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    public static let emptyStateTitle = Font.system(.title, design: .rounded).weight(.medium)
    public static let sectionTitle = Font.title2.bold()
    public static let brandTitle = Font.title3.bold()
    public static let heading = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let chatBody = Font.system(size: 14)
    public static let chatInput = Font.system(size: 16, design: .rounded)
    public static let composerControl = Font.system(size: 13, weight: .medium, design: .rounded)
    public static let historyBody = Font.system(size: 14, design: .rounded)
    public static let historyCaption = Font.system(size: 12, design: .rounded)
    public static let historySection = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let historyTitle = Font.system(size: 17, weight: .bold, design: .rounded)
    public static let caption = Font.caption
    public static let captionStrong = Font.caption.bold()
    public static let footnote = Font.caption2
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    public static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    public static let brandCaption = Font.system(size: 8, weight: .semibold, design: .monospaced)
    public static let avatar = Font.system(size: 23, weight: .medium, design: .rounded)
    public static let navigationIcon = Font.system(size: DLSSize.iconCompact, weight: .medium)
    public static let toolbarIcon = Font.system(size: DLSSize.iconToolbar, weight: .medium)
    public static let toolbarLabel = Font.system(size: 13, weight: .medium, design: .rounded)
    public static let toolbarTitle = Font.system(size: 12, weight: .medium, design: .rounded)
    public static let brandIcon = Font.title
    public static let featureIcon = Font.system(size: DLSSize.iconLarge)
    public static let heroIcon = Font.system(size: DLSSize.avatar, weight: .light)
}
