import SwiftUI

public enum DLSTheme: String, CaseIterable, Sendable {
  case light, dark
  public var colors: DLSColors { self == .dark ? .dark : .light }
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

private struct DLSThemeKey: EnvironmentKey {
  static let defaultValue = DLSTheme.light
}

extension EnvironmentValues {
  public var dlsTheme: DLSTheme {
    get { self[DLSThemeKey.self] }
    set { self[DLSThemeKey.self] = newValue }
  }
}

private struct DLSAppearanceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let appearance: DLSAppearance
  func body(content: Content) -> some View {
    let theme = appearance.resolved(for: colorScheme)
    content.environment(\.dlsTheme, theme)
      .tint(theme.colors.accent)
      .foregroundStyle(theme.colors.textPrimary)
      .font(DLSTypography.body)
      .preferredColorScheme(appearance.colorScheme)
  }
}

extension View {
  /// Apply once at a presentation root; descendants read semantic roles from `dlsTheme`.
  public func dlsAppearance(_ appearance: DLSAppearance = .system) -> some View {
    modifier(DLSAppearanceModifier(appearance: appearance))
  }
}
