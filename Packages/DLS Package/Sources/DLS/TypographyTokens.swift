import SwiftUI

/// Use semantic text styles for content so system accessibility sizing can participate.
public enum DLSTypography {
    /// Shared point size for the AppKit terminal emulator.
    public static let terminalPointSize: CGFloat = 13
    private static func ui(_ size: CGFloat) -> Font {
        let profile = DLSVisualPreferences.currentProfile
        return profile.font(size: max(8, size + profile.uiSize - 14))
    }
    public static var catalogTitle: Font { ui(26).weight(.semibold) }
    public static var pageTitle: Font { ui(26).weight(.semibold) }
    public static var emptyStateTitle: Font { ui(22).weight(.medium) }
    public static var sectionTitle: Font { ui(17).bold() }
    public static var brandTitle: Font { ui(15).bold() }
    public static var heading: Font { ui(13).weight(.semibold) }
    public static var body: Font { ui(13) }
    public static var callout: Font { ui(12) }
    public static var chatBody: Font { ui(14) }
    public static var chatInput: Font { ui(16) }
    public static var composerControl: Font { ui(13) }
    public static let historyPointSize: CGFloat = 13
    public static var historyBody: Font { ui(historyPointSize) }
    public static var historyCaption: Font { historyBody }
    public static var historySection: Font { historyBody }
    public static var historyTitle: Font { ui(historyPointSize).weight(.medium) }
    public static var historyProviderTitle: Font { historyTitle }
    public static var caption: Font { ui(10) }
    public static var captionStrong: Font { ui(10).bold() }
    public static var footnote: Font { ui(9) }
    public static var monoCaption: Font {
        let profile = DLSVisualPreferences.currentProfile
        return profile.font(size: profile.codeSize, code: true)
    }
    public static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    public static let brandCaption = Font.system(size: 8, weight: .semibold, design: .monospaced)
    public static let avatar = Font.system(size: 23, weight: .medium, design: .rounded)
    public static let navigationIcon = Font.system(size: DLSSize.iconCompact, weight: .medium)
    public static let toolbarIcon = Font.system(size: DLSSize.iconToolbar, weight: .medium)
    public static var toolbarLabel: Font { ui(13) }
    public static var toolbarTitle: Font { ui(12) }
    public static let brandIcon = Font.title
    public static let featureIcon = Font.system(size: DLSSize.iconLarge)
    public static let heroIcon = Font.system(size: DLSSize.avatar, weight: .light)
}

/// Text roles resolve against the live theme, including each window's light or dark profile.
public enum DLSTextStyle: CaseIterable, Hashable, Sendable {
    case catalogTitle, pageTitle, emptyStateTitle, sectionTitle, brandTitle, heading, body, callout, chatBody, chatInput, composerControl, historyBody, historyCaption, historySection, historyTitle, historyProviderTitle, caption, captionStrong, footnote, monoCaption, toolbarLabel, toolbarTitle, eyebrow, brandCaption

    public func font(profile: DLSVisualProfile) -> Font {
        switch self {
        case .catalogTitle: profile.font(size: max(8, 26 + profile.uiSize - 14)).weight(.semibold)
        case .pageTitle: profile.font(size: max(8, 26 + profile.uiSize - 14)).weight(.semibold)
        case .emptyStateTitle: profile.font(size: max(8, 22 + profile.uiSize - 14)).weight(.medium)
        case .sectionTitle: profile.font(size: max(8, 17 + profile.uiSize - 14)).weight(.bold)
        case .brandTitle: profile.font(size: max(8, 15 + profile.uiSize - 14)).weight(.bold)
        case .heading: profile.font(size: max(8, 13 + profile.uiSize - 14)).weight(.semibold)
        case .body: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .callout: profile.font(size: max(8, 12 + profile.uiSize - 14))
        case .chatBody: profile.font(size: max(8, 14 + profile.uiSize - 14))
        case .chatInput: profile.font(size: max(8, 16 + profile.uiSize - 14))
        case .composerControl: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .historyBody: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .historyCaption: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .historySection: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .historyTitle: profile.font(size: max(8, 13 + profile.uiSize - 14)).weight(.medium)
        case .historyProviderTitle: profile.font(size: max(8, 13 + profile.uiSize - 14)).weight(.medium)
        case .caption: profile.font(size: max(8, 10 + profile.uiSize - 14))
        case .captionStrong: profile.font(size: max(8, 10 + profile.uiSize - 14)).weight(.bold)
        case .footnote: profile.font(size: max(8, 9 + profile.uiSize - 14))
        case .monoCaption: profile.font(size: profile.codeSize, code: true)
        case .toolbarLabel: profile.font(size: max(8, 13 + profile.uiSize - 14))
        case .toolbarTitle: profile.font(size: max(8, 12 + profile.uiSize - 14))
        case .eyebrow: profile.font(size: max(8, 10 + profile.uiSize - 14)).weight(.semibold)
        case .brandCaption: profile.font(size: max(8, 8 + profile.uiSize - 14)).weight(.semibold)
        }
    }
}

private struct DLSTextStyleModifier: ViewModifier {
    @Environment(\.dlsTheme) private var theme
    let style: DLSTextStyle

    func body(content: Content) -> some View {
        content.font(style.font(profile: theme.profile))
    }
}

extension View {
    /// Follow font changes without recreating views or losing focus and scroll position.
    public func dlsFont(_ style: DLSTextStyle) -> some View {
        modifier(DLSTextStyleModifier(style: style))
    }
}
