import SwiftUI

public struct DLSTheme: RawRepresentable, CaseIterable, Equatable, Sendable {
  public let rawValue: String
  public var preferences = DLSVisualPreferences()
  // RawRepresentable's default equality compares only the palette name. Environment
  // updates must also observe custom colors and the other visual preferences.
  public static func == (lhs: DLSTheme, rhs: DLSTheme) -> Bool {
    lhs.rawValue == rhs.rawValue && lhs.preferences == rhs.preferences
  }
  private init(_ name: String) { rawValue = name }
  public init?(rawValue: String) {
    guard Self.allCases.contains(where: { $0.rawValue == rawValue }) else { return nil }
    self.rawValue = rawValue
  }
  public static let allCases: [DLSTheme] = [.light, .dark, .oceanLight, .oceanDark, .sepiaLight, .sepiaDark]
  public var isDark: Bool { rawValue == "dark" || rawValue == "oceanDark" || rawValue == "sepiaDark" }
  public var profile: DLSVisualProfile { preferences.profile(dark: isDark) }
  public static let light = DLSTheme("light")
  public static let dark = DLSTheme("dark")
  public static let oceanLight = DLSTheme("oceanLight")
  public static let oceanDark = DLSTheme("oceanDark")
  public static let sepiaLight = DLSTheme("sepiaLight")
  public static let sepiaDark = DLSTheme("sepiaDark")
  public var colors: DLSColors {
    let base: DLSColors = switch rawValue {
    case "dark": .dark
    case "oceanLight": .oceanLight
    case "oceanDark": .oceanDark
    case "sepiaLight": .sepiaLight
    case "sepiaDark": .sepiaDark
    default: .light
    }
    return base.customized(profile: profile, contrast: preferences.contrast)
  }
}

public enum DLSColorTheme: String, CaseIterable, Identifiable, Sendable {
  case standard, ocean, sepia
  public var id: String { rawValue }
  public var title: String { self == .standard ? "Default" : rawValue.capitalized }
  public func resolved(dark: Bool) -> DLSTheme {
    switch self {
    case .standard: dark ? .dark : .light
    case .ocean: dark ? .oceanDark : .oceanLight
    case .sepia: dark ? .sepiaDark : .sepiaLight
    }
  }
}

public enum DLSAppearance: String, CaseIterable, Identifiable, Sendable {
  case system, light, dark
  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
  public func resolved(for colorScheme: ColorScheme) -> DLSTheme {
    switch self {
    case .system: colorScheme == .dark ? .dark : .light
    case .light: .light
    case .dark: .dark
    }
  }
  fileprivate var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

private struct DLSReduceMotionKey: EnvironmentKey {
  static let defaultValue = false
}

private struct DLSThemeKey: EnvironmentKey {
  static let defaultValue = DLSTheme.light
}

extension EnvironmentValues {
  public var dlsReduceMotion: Bool {
    get { self[DLSReduceMotionKey.self] }
    set { self[DLSReduceMotionKey.self] = newValue }
  }
  public var dlsTheme: DLSTheme {
    get { self[DLSThemeKey.self] }
    set { self[DLSThemeKey.self] = newValue }
  }
}

private struct DLSAppearanceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage(DLSVisualPreferences.storageKey) private var visualData = Data()
  let appearance: DLSAppearance
  let colorTheme: DLSColorTheme
  func body(content: Content) -> some View {
    let settings = DLSVisualPreferences.decode(visualData)
    let dark = appearance.resolved(for: colorScheme).isDark
    let profile = settings.profile(dark: dark)
    let palette = visualData.isEmpty ? colorTheme : (DLSColorTheme(rawValue: profile.theme) ?? colorTheme)
    var theme = palette.resolved(dark: dark)
    theme.preferences = settings
    let reduceMotion = settings.reduceMotion == "System" ? systemReduceMotion : settings.reduceMotion == "On"
    return content.environment(\.dlsTheme, theme)
      .environment(\.colorScheme, theme.colors.usesDarkSurfaces ? .dark : .light)
      .tint(theme.colors.accent)
      .foregroundStyle(theme.colors.textPrimary)
      .font(profile.font(size: profile.uiSize))
      .environment(\.dlsReduceMotion, reduceMotion)
      .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
      .preferredColorScheme(appearance.colorScheme)
  }
}

extension View {
  /// Apply once at a presentation root; descendants read semantic roles from `dlsTheme`.
  public func dlsAppearance(_ appearance: DLSAppearance = .system, colorTheme: DLSColorTheme = .standard) -> some View {
    modifier(DLSAppearanceModifier(appearance: appearance, colorTheme: colorTheme))
  }
}
