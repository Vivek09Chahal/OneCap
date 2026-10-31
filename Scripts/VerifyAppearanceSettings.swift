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
        precondition(DLSVisualPreferences.decode(encoded) == preferences, "Every option must survive saving")
        precondition(preferences.profile(dark: true).theme == "ocean")
        precondition(preferences.profile(dark: false).theme == "standard")
        precondition(preferences.shared.nsFont(size: 17).pointSize == 17)
        precondition(preferences.shared.nsFont(size: 16, code: true).isFixedPitch)
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
        precondition(observedBackground == "#181818")
        for style in DLSTextStyle.allCases {
            precondition(observedFonts[style] == style.font(profile: preferences.dark))
        }
        var livePreferences = preferences
        livePreferences.dark.background = "#345678"
        livePreferences.dark.uiFont = "Menlo"
        livePreferences.dark.uiSize = 21
        livePreferences.dark.uiWeight = "Bold"
        UserDefaults.standard.set(try JSONEncoder().encode(livePreferences), forKey: DLSVisualPreferences.storageKey)
        for _ in 0..<30 {
            liveHost.layoutSubtreeIfNeeded()
            if observedBackground == "#345678",
               observedFonts[.historyBody] == DLSTextStyle.historyBody.font(profile: livePreferences.dark) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(observedBackground == "#345678", "Mounted views must update without switching tabs")
        for style in DLSTextStyle.allCases {
            precondition(observedFonts[style] == style.font(profile: livePreferences.dark),
                         "Every text role, including the sidebar, must update in the mounted view")
        }
        liveWindow.close()
        UserDefaults.standard.set(encoded, forKey: DLSVisualPreferences.storageKey)
        for (name, mode, width) in [("dark", DLSAppearance.dark, 900.0), ("light", .light, 760.0), ("compact", .dark, 600.0)] {
            let root = AppearanceSettingsView(appearance: .constant(mode), showAdvanced: true)
                .padding(24).frame(width: width)
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
        print("Live background and app-wide font updates, persistence, separate modes, and color checks passed. Three Settings layouts rendered.")
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
