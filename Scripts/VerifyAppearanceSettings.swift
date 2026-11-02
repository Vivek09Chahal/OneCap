import AppKit
import DLS
import SwiftUI
@testable import OneCap

/// Uses an isolated preferences domain and local views; never opens a provider or chat history.
@main struct VerifyAppearanceSettings {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var preferences = DLSVisualPreferences()
        preferences.shared.background = "#123456"
        preferences.shared.foreground = "#FFFFFF"
        preferences.shared.accent = "#FF8800"
        preferences.shared.uiFont = "Helvetica Neue"
        preferences.shared.codeFont = "Menlo"
        preferences.shared.uiSize = 17
        preferences.shared.codeSize = 16
        preferences.separateModes = true
        preferences.light = preferences.shared
        preferences.dark = preferences.shared
        preferences.dark.theme = "ocean"
        preferences.dark.background = "#181818"
        preferences.reduceMotion = "On"
        preferences.pointerCursors = true
        preferences.translucentSidebar = true
        preferences.diffMarkers = "Markers"
        preferences.dockIcon = "Terminal"
        preferences.fontSmoothing = false
        let encoded = try JSONEncoder().encode(preferences)
        let simplified = DLSVisualPreferences.decode(encoded)
        precondition(simplified == preferences.simplified())
        precondition(!simplified.separateModes && !simplified.translucentSidebar)
        precondition(simplified.contrast == 60 && simplified.dockIcon == "Default")
        precondition(simplified.profile(dark: true) == simplified.profile(dark: false))
        precondition(simplified.shared.uiFont == "System" && simplified.shared.uiSize == 14)
        precondition(simplified.shared.codeFont == "System" && simplified.shared.codeSize == 13)
        precondition(simplified.reduceMotion == "On" && simplified.pointerCursors)
        precondition(simplified.diffMarkers == "Markers" && !simplified.fontSmoothing)
        precondition(preferences.profile(dark: true).theme == "ocean")
        precondition(preferences.profile(dark: false).theme == "standard")
        precondition(preferences.shared.nsFont(size: 17).pointSize == 17)
        precondition(preferences.shared.nsFont(size: 16, code: true) == preferences.shared.nsFont(size: 16))
        precondition(preferences.shared.nsFont(size: 16, content: true) == preferences.shared.nsFont(size: 16))
        precondition(DLSVisualPreferences.decode(Data("invalid".utf8)) == DLSVisualPreferences())
        var theme = DLSTheme.dark
        theme.preferences = preferences
        precondition(theme.colors.background.visualHexString == "#181818")
        precondition(theme.colors.textPrimary.visualHexString == "#FFFFFF")
        precondition(theme.colors.accent.visualHexString == "#FF8800")
        var updatedTheme = theme
        updatedTheme.preferences.dark.background = "#345678"
        precondition(theme != updatedTheme, "Color changes must invalidate the theme environment")
        precondition(theme == theme, "Identical themes must remain equal")

        // Custom backgrounds tint every major surface, including across appearance modes.
        for base in [DLSTheme.light, .dark] {
            var custom = base
            custom.preferences.shared.background = "#123456"
            precondition(custom.colors.background.visualHexString == "#123456")
            precondition(custom.colors.textPrimary.visualHexString == "#F2F2F2")
            precondition(custom.colors.surface.visualHexString != base.colors.surface.visualHexString)
            precondition(custom.colors.sidebar.visualHexString != base.colors.sidebar.visualHexString)
            precondition(custom.colors.composer.visualHexString != base.colors.composer.visualHexString)
            precondition(custom.colors.selection.visualHexString != base.colors.selection.visualHexString)
            precondition(custom.colors.userMessage.visualHexString != base.colors.userMessage.visualHexString)
            custom.preferences.shared.background = "#FFFFFF"
            precondition(custom.colors.textPrimary.visualHexString == "#202020")
        }
        // Every preset and custom accent needs readable text and a readable filled-button label.
        var checkedPalettes = 0
        for base in DLSTheme.allCases {
            for background in ["", "#FFFFFF", "#101010", "#123456", "#747474", "#777777"] {
                for accent in ["", "#FFFFFF", "#000000", "#FFFF00", "#4589FF", "#E66BA3"] {
                    for contrast in [0.0, 60.0, 100.0] {
                        var custom = base
                        custom.preferences.shared.background = background
                        custom.preferences.shared.accent = accent
                        // Deliberately conflicting foreground overrides must remain readable.
                        custom.preferences.shared.foreground = background
                        custom.preferences.contrast = contrast
                        let colors = custom.colors
                        let surfaces = [colors.background, colors.surface, colors.sidebar,
                                        colors.composer, colors.selection]
                        for foreground in [colors.textPrimary, colors.textSecondary, colors.textTertiary,
                                           colors.accent, colors.success, colors.warning, colors.danger] {
                            for surface in surfaces {
                                precondition(contrastRatio(foreground, surface) >= 4.49,
                                             "Unreadable palette: \(base.rawValue) \(background) \(accent)")
                            }
                        }
                        for surface in [colors.userMessage, colors.accentSubtle, colors.accentMuted] {
                            precondition(contrastRatio(colors.textPrimary, surface) >= 4.49)
                        }
                        precondition(contrastRatio(colors.onAccent, colors.accent) >= 4.5)
                        if background == "#FFFFFF" { precondition(!colors.usesDarkSurfaces) }
                        if background == "#101010" { precondition(colors.usesDarkSurfaces) }
                        checkedPalettes += 1
                    }
                }
            }
        }
        print("Contrast checks passed for \(checkedPalettes) preset/custom combinations.")
        var presetProfile = preferences.shared
        for preset in DLSColorTheme.allCases {
            presetProfile.background = "#123456"
            presetProfile.foreground = "#FFFFFF"
            presetProfile.accent = "#FF8800"
            precondition(presetProfile.hasCustomColors)
            presetProfile.apply(preset: preset)
            precondition(presetProfile.theme == preset.rawValue && !presetProfile.hasCustomColors)
            precondition(presetProfile.uiFont == "Helvetica Neue" && presetProfile.uiSize == 17)
            precondition(presetProfile.codeFont == "Menlo" && presetProfile.codeSize == 16)
        }

        // The executable uses its own domain, separate from the installed app.
        UserDefaults.standard.set(encoded, forKey: DLSVisualPreferences.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: DLSVisualPreferences.storageKey) }
        // Keep the same mounted view while changing storage, as the Settings color well does.
        var observedBackground = ""
        var observedFonts: [DLSTextStyle: Font] = [:]
        let liveHost = NSHostingView(rootView: VStack {
            LiveThemeProbe { observedBackground = $0 }
            ForEach(DLSTextStyle.allCases, id: \.self) { style in
                LiveFontProbe { observedFonts[style] = $0 }.dlsFont(style)
            }
        }.dlsAppearance(.dark))
        let liveWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        liveWindow.isReleasedWhenClosed = false
        liveWindow.contentView = liveHost
        for _ in 0..<10 { liveHost.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        precondition(observedBackground == "#123456")
        for style in DLSTextStyle.allCases {
            precondition(observedFonts[style] == style.font(profile: simplified.shared))
        }
        var livePreferences = preferences
        livePreferences.shared.background = "#345678"
        livePreferences.shared.uiFont = "Menlo"
        livePreferences.shared.uiSize = 21
        livePreferences.shared.uiWeight = "Bold"
        UserDefaults.standard.set(try JSONEncoder().encode(livePreferences), forKey: DLSVisualPreferences.storageKey)
        for _ in 0..<30 {
            liveHost.layoutSubtreeIfNeeded()
            if observedBackground == "#345678",
               observedFonts[.historyBody] == DLSTextStyle.historyBody.font(profile: livePreferences.simplified().shared) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(observedBackground == "#345678", "Mounted views must update without switching tabs")
        for style in DLSTextStyle.allCases {
            precondition(observedFonts[style] == style.font(profile: livePreferences.simplified().shared),
                         "Every text role, including the sidebar, must update in the mounted view")
        }
        liveWindow.close()
        UserDefaults.standard.set(encoded, forKey: DLSVisualPreferences.storageKey)
        for (name, mode, width) in [("dark", DLSAppearance.dark, 900.0), ("light", .light, 760.0), ("compact", .dark, 600.0)] {
            let root = AppearanceFixture(mode: mode, width: width)
                .chatAppearancePreferences().dlsAppearance(mode)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 2200),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
            host.setFrameSize(NSSize(width: width, height: max(2200, host.fittingSize.height)))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing Settings render") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/OneCap-appearance-\(name).png"))
            precondition(host.bounds.height >= 1000, "Advanced controls must render")
            window.close()
        }
        print("Live background updates, unified fonts, legacy preference normalization, and color checks passed. Three Settings layouts rendered.")
    }
}

private struct LiveThemeProbe: View {
    @Environment(\.dlsTheme) private var theme
    let report: (String) -> Void

    var body: some View {
        theme.colors.background
            .onChange(of: theme, initial: true) { _, updated in
                report(updated.colors.background.visualHexString)
            }
    }
}

private struct LiveFontProbe: View {
    @Environment(\.font) private var font
    let report: (Font) -> Void

    var body: some View {
        Color.clear.onChange(of: font, initial: true) { _, updated in
            if let updated { report(updated) }
        }
    }
}

private struct AppearanceFixture: View {
    @Environment(\.dlsTheme) private var theme
    let mode: DLSAppearance
    let width: Double

    var body: some View {
        AppearanceSettingsView(appearance: .constant(mode), showAdvanced: true)
            .padding(24).frame(width: width)
            .background(theme.colors.background)
    }
}

private func contrastRatio(_ first: Color, _ second: Color) -> Double {
    func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        let channels = [resolved.red, resolved.green, resolved.blue].map { value -> Double in
            let channel = Double(value)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    let a = luminance(first)
    let b = luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
