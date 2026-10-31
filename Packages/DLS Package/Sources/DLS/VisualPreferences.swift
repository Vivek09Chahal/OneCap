#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

public struct DLSVisualProfile: Codable, Equatable, Sendable {
    public var theme = "standard"
    public var accent = ""
    public var background = ""
    public var foreground = ""
    public var uiFont = "System"
    public var uiSize = 14.0
    public var uiWeight = "Regular"
    public var contentFont = "Same as UI font"
    public var contentWeight = "Regular"
    public var codeFont = "System"
    public var codeSize = 13.0
    public var codeWeight = "Regular"
    public init() {}

    public var hasCustomColors: Bool { !background.isEmpty || !foreground.isEmpty || !accent.isEmpty }

    /// A preset replaces color overrides while preserving typography and other preferences.
    public mutating func apply(preset: DLSColorTheme) {
        theme = preset.rawValue
        background = ""
        foreground = ""
        accent = ""
    }

    public func font(size: CGFloat, code: Bool = false, content: Bool = false) -> Font {
        #if canImport(AppKit)
        Font(nsFont(size: size, code: code, content: content))
        #else
        Font.system(size: size, design: code ? .monospaced : .default)
        #endif
    }
    #if canImport(AppKit)
    public func nsFont(size: CGFloat, code: Bool = false, content: Bool = false) -> NSFont {
        let family = code ? codeFont : content && contentFont != "Same as UI font" ? contentFont : uiFont
        let style = code ? codeWeight : content && contentFont != "Same as UI font" ? contentWeight : uiWeight
        let weight: NSFont.Weight = style == "Bold" ? .bold : style == "Medium" ? .medium : style == "Light" ? .light : .regular
        let safeSize = size.isFinite ? min(48, max(8, size)) : 14
        if family == "System" {
            return code ? NSFont.monospacedSystemFont(ofSize: safeSize, weight: weight)
                : NSFont.systemFont(ofSize: safeSize, weight: weight)
        }
        return NSFontManager.shared.font(withFamily: family, traits: [],
                                         weight: style == "Bold" ? 9 : style == "Medium" ? 6 : style == "Light" ? 3 : 5,
                                         size: safeSize) ?? NSFont.systemFont(ofSize: safeSize, weight: weight)
    }
    #endif
}

public struct DLSVisualPreferences: Codable, Equatable, Sendable {
    public var shared = DLSVisualProfile()
    public var light = DLSVisualProfile()
    public var dark = DLSVisualProfile()
    public var separateModes = false
    public var translucentSidebar = false
    public var contrast = 60.0
    public var reduceMotion = "System"
    public var diffMarkers = "Color"
    public var pointerCursors = false
    public var dockIcon = "Default"
    public var fontSmoothing = true
    public init() {}
    public static let storageKey = "visualPreferences"
    public static func decode(_ data: Data) -> Self { (try? JSONDecoder().decode(Self.self, from: data)) ?? Self() }
    public static var saved: Self { decode(UserDefaults.standard.data(forKey: storageKey) ?? Data()) }
    public func profile(dark isDark: Bool) -> DLSVisualProfile { separateModes ? (isDark ? dark : light) : shared }
    public static var currentProfile: DLSVisualProfile {
        let mode = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        let dark = mode == "dark" || mode == "system" && UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return saved.profile(dark: dark)
    }
}

extension Color {
    public static func visualHex(_ value: String) -> Color? {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return nil }
        return Color(.sRGB, red: Double((number >> 16) & 255) / 255,
                     green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, opacity: 1)
    }
    @MainActor public var visualHexString: String {
        let color = resolve(in: EnvironmentValues())
        return String(format: "#%02X%02X%02X", Int((color.red * 255).rounded()),
                      Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
    }
}
