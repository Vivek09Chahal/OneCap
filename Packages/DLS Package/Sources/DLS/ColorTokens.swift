import SwiftUI

/// Semantic roles shared by both palettes. Views never need to select raw colors.
public struct DLSColors: Sendable {
  public let background: Color
  public let surface: Color
  public let selection: Color
  public let sidebar: Color
  public let composer: Color
  public let onAccent: Color
  public let textPrimary: Color
  public let textSecondary: Color
  public let textTertiary: Color
  public let border: Color
  public let borderStrong: Color
  public let accent: Color
  public let accentSubtle: Color
  public let accentMuted: Color
  public let success: Color
  public let warning: Color
  public let danger: Color
  public let userMessage: Color

  public static let light = DLSColors(
    background: Color(hex: 0xFFFFFF), surface: Color(hex: 0xF0F0F0),
    selection: Color(hex: 0xE2E2E2), sidebar: Color(hex: 0xF7F7F7), composer: Color(hex: 0xF2F2F2), onAccent: Color(hex: 0xFFFFFF),
    textPrimary: Color(hex: 0x202020), textSecondary: Color(hex: 0x636363),
    textTertiary: Color(hex: 0x737373), border: Color(hex: 0xE2E2E2),
    borderStrong: Color(hex: 0xC6C6C6), accent: Color(hex: 0xB94D1C),
    accentSubtle: Color(hex: 0xF5E3D9), accentMuted: Color(hex: 0xFCF4EF),
    success: Color(hex: 0x337A4E), warning: Color(hex: 0x946500), danger: Color(hex: 0xBC3838),
    userMessage: Color(hex: 0xF5DFD3))

  public static let dark = DLSColors(
    background: Color(hex: 0x181818), surface: Color(hex: 0x282828),
    selection: Color(hex: 0x353535), sidebar: Color(hex: 0x202020), composer: Color(hex: 0x333333), onAccent: Color(hex: 0xFFFFFF),
    textPrimary: Color(hex: 0xF2F2F2), textSecondary: Color(hex: 0xACACAC),
    textTertiary: Color(hex: 0x959595), border: Color(hex: 0x353535),
    borderStrong: Color(hex: 0x4A4A4A), accent: Color(hex: 0xE3662D),
    accentSubtle: Color(hex: 0x3D302A), accentMuted: Color(hex: 0x2B2420),
    success: Color(hex: 0x82BE96), warning: Color(hex: 0xDCB76A), danger: Color(hex: 0xED9696),
    userMessage: Color(hex: 0x884321))

  public static let oceanLight = palette(dark: false, background: 0xF5F9FC, surface: 0xE7EFF5,
    sidebar: 0xEDF3F8, selection: 0xD5E3EF, accent: 0x176496)
  public static let oceanDark = palette(dark: true, background: 0x141D27, surface: 0x202E3C,
    sidebar: 0x192531, selection: 0x304357, accent: 0x79BCE8)
  public static let sepiaLight = palette(dark: false, background: 0xFCF7ED, surface: 0xF0E7D8,
    sidebar: 0xF5EEDF, selection: 0xE5D8C3, accent: 0x8C4E26)
  public static let sepiaDark = palette(dark: true, background: 0x231F1A, surface: 0x302A23,
    sidebar: 0x29241E, selection: 0x44392D, accent: 0xE5AE78)

  func customized(profile: DLSVisualProfile, contrast: Double) -> DLSColors {
    let customBackground = Color.visualHex(profile.background)
    let bg = customBackground ?? background
    let readable = Color.readableForeground(for: profile.background) ?? textPrimary
    let fg = Color.visualHex(profile.foreground) ?? readable
    let tint = Color.visualHex(profile.accent) ?? accent
    let level = min(1, max(0, contrast / 100))
    return DLSColors(background: bg,
      surface: customBackground == nil ? surface : bg.blended(with: readable, by: 0.06),
      selection: customBackground == nil ? selection : bg.blended(with: readable, by: 0.14),
      sidebar: customBackground == nil ? sidebar : bg.blended(with: readable, by: 0.03),
      composer: customBackground == nil ? composer : bg.blended(with: readable, by: 0.08),
      onAccent: onAccent, textPrimary: fg,
      textSecondary: fg.opacity(0.45 + level * 0.4), textTertiary: fg.opacity(0.3 + level * 0.4),
      border: fg.opacity(0.06 + level * 0.14), borderStrong: fg.opacity(0.1 + level * 0.25),
      accent: tint, accentSubtle: tint.opacity(0.16), accentMuted: tint.opacity(0.08),
      success: success, warning: warning, danger: danger,
      userMessage: customBackground == nil ? userMessage : bg.blended(with: tint, by: 0.18))
  }

  private static func palette(dark: Bool, background: UInt32, surface: UInt32,
                              sidebar: UInt32, selection: UInt32, accent: UInt32) -> DLSColors {
    let base: DLSColors = dark ? .dark : .light
    return DLSColors(
      background: Color(hex: background), surface: Color(hex: surface),
      selection: Color(hex: selection), sidebar: Color(hex: sidebar),
      composer: Color(hex: surface), onAccent: dark ? Color(hex: 0x202020) : .white,
      textPrimary: base.textPrimary, textSecondary: base.textSecondary, textTertiary: base.textTertiary,
      border: Color(hex: selection), borderStrong: base.borderStrong, accent: Color(hex: accent),
      accentSubtle: Color(hex: accent).opacity(0.16), accentMuted: Color(hex: accent).opacity(0.08),
      success: base.success, warning: base.warning, danger: base.danger,
      userMessage: Color(hex: selection))
  }

}

extension Color {
  fileprivate func blended(with other: Color, by fraction: Double) -> Color {
    let source = resolve(in: EnvironmentValues())
    let target = other.resolve(in: EnvironmentValues())
    let amount = Float(fraction)
    return Color(.sRGB,
      red: Double(source.red + (target.red - source.red) * amount),
      green: Double(source.green + (target.green - source.green) * amount),
      blue: Double(source.blue + (target.blue - source.blue) * amount), opacity: 1)
  }

  /// Choose readable default text even when a custom background differs from the selected mode.
  fileprivate static func readableForeground(for hex: String) -> Color? {
    guard Color.visualHex(hex) != nil,
          let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
    let channels = [16, 8, 0].map { shift -> Double in
      let component = Double((value >> shift) & 255) / 255
      return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    return luminance > 0.179 ? Color(hex: 0x202020) : Color(hex: 0xF2F2F2)
  }

  fileprivate init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: 1)
  }
}
