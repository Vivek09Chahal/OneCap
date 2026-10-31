import DLS
import SwiftUI

/// Chat readability preferences complement the shared app typography.
enum ChatDensity: String, CaseIterable, Identifiable {
    case compact, comfortable, spacious
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .compact: 0.65
        case .comfortable: 1
        case .spacious: 1.35
        }
    }
}

struct ChatAppearance: Equatable {
    var fontSize: Double = 14
    var density: ChatDensity = .comfortable
    var profile = DLSVisualProfile()
    var textSize: CGFloat {
        let base = fontSize.isFinite ? fontSize : 14
        let appSize = profile.uiSize.isFinite ? profile.uiSize : 14
        return CGFloat(min(30, max(12, base + appSize - 14)))
    }
    func spacing(_ value: CGFloat) -> CGFloat { value * density.scale }
}

private struct ChatAppearanceKey: EnvironmentKey {
    static let defaultValue = ChatAppearance()
}

extension EnvironmentValues {
    var chatAppearance: ChatAppearance {
        get { self[ChatAppearanceKey.self] }
        set { self[ChatAppearanceKey.self] = newValue }
    }
}

private struct ChatAppearanceModifier: ViewModifier {
    @Environment(\.dlsTheme) private var theme
    @AppStorage("chatFontSize") private var fontSize = 14.0
    @AppStorage("chatDensity") private var density: ChatDensity = .comfortable

    func body(content: Content) -> some View {
        content.environment(\.chatAppearance, ChatAppearance(fontSize: fontSize, density: density, profile: theme.profile))
    }
}

extension View {
    func chatAppearancePreferences() -> some View { modifier(ChatAppearanceModifier()) }
}
