import SwiftUI

/// Semantic roles shared by both palettes. Views never need to select raw colors.
public struct DLSColors: Sendable {
  public let background: Color
  public let surface: Color
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
    sidebar: Color(hex: 0xF7F7F7), composer: Color(hex: 0xF2F2F2), onAccent: Color(hex: 0xFFFFFF),
    textPrimary: Color(hex: 0x202020), textSecondary: Color(hex: 0x636363),
    textTertiary: Color(hex: 0x737373), border: Color(hex: 0xE2E2E2),
    borderStrong: Color(hex: 0xC6C6C6), accent: Color(hex: 0xB94D1C),
    accentSubtle: Color(hex: 0xF5E3D9), accentMuted: Color(hex: 0xFCF4EF),
    success: Color(hex: 0x337A4E), warning: Color(hex: 0x946500), danger: Color(hex: 0xBC3838),
    userMessage: Color(hex: 0xF5DFD3))

  public static let dark = DLSColors(
    background: Color(hex: 0x181818), surface: Color(hex: 0x282828),
    sidebar: Color(hex: 0x202020), composer: Color(hex: 0x333333), onAccent: Color(hex: 0xFFFFFF),
    textPrimary: Color(hex: 0xF2F2F2), textSecondary: Color(hex: 0xACACAC),
    textTertiary: Color(hex: 0x959595), border: Color(hex: 0x353535),
    borderStrong: Color(hex: 0x4A4A4A), accent: Color(hex: 0xE3662D),
    accentSubtle: Color(hex: 0x3D302A), accentMuted: Color(hex: 0x2B2420),
    success: Color(hex: 0x82BE96), warning: Color(hex: 0xDCB76A), danger: Color(hex: 0xED9696),
    userMessage: Color(hex: 0x884321))
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: 1)
  }
}
