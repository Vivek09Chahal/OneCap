import AppKit
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Binding var appearance: DLSAppearance
    @AppStorage("colorTheme") private var colorTheme: DLSColorTheme = .standard
    @AppStorage("chatFontSize") private var fontSize = 14.0
    @AppStorage("chatDensity") private var density: ChatDensity = .comfortable
    @AppStorage(DLSVisualPreferences.storageKey) private var visualData = Data()
    @Environment(\.dlsTheme) private var theme
    @State private var advanced = false
    private var editingDark: Bool { theme.isDark }
    @State private var importError: String?

    init(appearance: Binding<DLSAppearance>, showAdvanced: Bool = false) {
        _appearance = appearance
        _advanced = State(initialValue: showAdvanced)
    }

    private var settings: DLSVisualPreferences {
        var value = DLSVisualPreferences.decode(visualData)
        if visualData.isEmpty { value.shared.theme = colorTheme.rawValue }
        return value
    }
    private var profile: DLSVisualProfile { settings.profile(dark: editingDark) }
    private var editingTheme: DLSTheme {
        var value = (DLSColorTheme(rawValue: profile.theme) ?? .standard).resolved(dark: editingDark)
        value.preferences = settings
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Text("Visual style").dlsFont(.heading)
            VStack(spacing: 16) {
                row("Mode") {
                    Picker("Mode", selection: $appearance) {
                        ForEach(DLSAppearance.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 240)
                }
            }.cardSurface()

            VStack(spacing: 16) {
                row("Preset", subtitle: "Choose a starting palette, or customize the colors below.") {
                    Button { importTheme() } label: { Image(systemName: "square.and.arrow.down") }
                        .help("Import appearance from a JSON file").accessibilityLabel("Import theme")
                    Button { exportTheme() } label: { Image(systemName: "square.and.arrow.up") }
                        .help("Export appearance to a JSON file").accessibilityLabel("Export theme")
                    Button {
                        NSPasteboard.general.clearContents()
                        if let text = String(data: visualData.isEmpty ? ((try? JSONEncoder().encode(settings)) ?? Data()) : visualData, encoding: .utf8) {
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy appearance as JSON").accessibilityLabel("Copy theme")
                    Picker("Preset", selection: Binding(get: {
                        profile.hasCustomColors ? "custom" : profile.theme
                    }, set: { name in
                        guard let preset = DLSColorTheme(rawValue: name) else { return }
                        updateProfile { $0.apply(preset: preset) }
                    })) {
                        ForEach(DLSColorTheme.allCases) { Text($0.title).tag($0.rawValue) }
                        if profile.hasCustomColors { Text("Custom").tag("custom") }
                    }.frame(width: 140).accessibilityIdentifier("settings-color-theme")
                }
                Divider()
                row("Accent") {
                    Picker("Accent", selection: profileBinding(\.accent)) {
                        Text("Theme default").tag("")
                        Text("Orange").tag("#E3662D")
                        Text("Blue").tag("#4589FF")
                        Text("Purple").tag("#A578E8")
                        Text("Green").tag("#4AAB76")
                        Text("Pink").tag("#E66BA3")
                        Text("Red").tag("#E35353")
                        if !["", "#E3662D", "#4589FF", "#A578E8", "#4AAB76", "#E66BA3", "#E35353"].contains(profile.accent) {
                            Text("Custom").tag(profile.accent)
                        }
                    }.frame(width: 150)
                    colorWell("Accent color", key: \.accent, fallback: editingTheme.colors.accent)
                }
                Divider()
                colorRow("Background", key: \.background, fallback: editingTheme.colors.background)
                Divider()
                colorRow("Foreground", key: \.foreground, fallback: editingTheme.colors.textPrimary)
            }.cardSurface()

            Text("Chat").dlsFont(.heading)
            VStack(alignment: .leading, spacing: 16) {
                sizeRow("Chat font size", value: $fontSize, range: 12...22)
                    .accessibilityIdentifier("settings-chat-font-size")
                Divider()
                row("Chat density") {
                    Picker("Chat density", selection: $density) {
                        ForEach(ChatDensity.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 280)
                        .accessibilityIdentifier("settings-chat-density")
                }
                Divider()
                Text("Preview").foregroundStyle(theme.colors.textSecondary)
                ChatMessageText(source: "A workspace that feels like yours.\n\nChoose a theme, text size, and spacing for comfortable reading.\n\n```swift\nprint(\"Hello, Edth\")\n```")
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("settings-chat-preview")
                Text("Changes save automatically and apply across windows.")
                    .dlsFont(.callout).foregroundStyle(theme.colors.textSecondary)
            }.cardSurface()

            HStack {
                Button { advanced.toggle() } label: {
                    Label("Advanced", systemImage: advanced ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain)
                Spacer()
                Button("Reset to defaults", action: reset)
                    .buttonStyle(.plain).foregroundStyle(theme.colors.textSecondary)
            }
            if advanced { advancedControls }
        }
        .alert("Could not load appearance", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private var advancedControls: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                row("Reduce motion", subtitle: "Reduce animations or follow your Mac’s setting.") {
                    Picker("Reduce motion", selection: binding(\.reduceMotion)) {
                        ForEach(["System", "On", "Off"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 200)
                }
            }.cardSurface()
            VStack(spacing: 16) {
                row("Diff markers", subtitle: "Show changes using color or +/− markers.") {
                    Picker("Diff markers", selection: binding(\.diffMarkers)) {
                        Text("Color").tag("Color")
                        Text("+/−").tag("Markers")
                    }.pickerStyle(.segmented).frame(width: 150)
                }
                Divider()
                toggleRow("Use pointer cursors", subtitle: "Show a pointer over buttons and links.", key: \.pointerCursors)
                Divider()
                toggleRow("Font smoothing", subtitle: "Use native macOS text anti-aliasing. Some views update after relaunch.", key: \.fontSmoothing)
            }.cardSurface()
        }
    }

    private func row<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let subtitle { Text(subtitle).dlsFont(.callout).foregroundStyle(theme.colors.textSecondary) }
            }.layoutPriority(1)
            Spacer(minLength: 12)
            content().labelsHidden()
        }.frame(minHeight: 30)
    }
    private func sizeRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        row(title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width: 50)
                .onChange(of: value.wrappedValue) { _, new in
                    let clamped = new.isFinite ? min(range.upperBound, max(range.lowerBound, new)) : range.lowerBound
                    if clamped != new { value.wrappedValue = clamped }
                }
            Text("pt").foregroundStyle(theme.colors.textSecondary)
            Stepper(title, value: value, in: range, step: 1).labelsHidden()
        }
    }
    private func colorWell(_ title: String, key: WritableKeyPath<DLSVisualProfile, String>, fallback: Color) -> some View {
        ColorPicker(title, selection: Binding(get: { Color.visualHex(profile[keyPath: key]) ?? fallback },
                                             set: { profileBinding(key).wrappedValue = $0.visualHexString }), supportsOpacity: false)
            .labelsHidden()
    }
    private func colorRow(_ title: String, key: WritableKeyPath<DLSVisualProfile, String>, fallback: Color) -> some View {
        row(title) {
            colorWell(title, key: key, fallback: fallback)
            TextField(fallback.visualHexString, text: profileBinding(key)).frame(width: 88).textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(title) hex color")
            Button { profileBinding(key).wrappedValue = "" } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Use theme default").accessibilityLabel("Reset \(title.lowercased())")
        }
    }
    private func toggleRow(_ title: String, subtitle: String? = nil, key: WritableKeyPath<DLSVisualPreferences, Bool>) -> some View {
        row(title, subtitle: subtitle) { Toggle(title, isOn: binding(key)).labelsHidden().toggleStyle(.switch) }
    }
    private func binding<T>(_ key: WritableKeyPath<DLSVisualPreferences, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { new in var value = settings; value[keyPath: key] = new; save(value) })
    }
    private func profileBinding<T>(_ key: WritableKeyPath<DLSVisualProfile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: key] }, set: { new in
            updateProfile { $0[keyPath: key] = new }
        })
    }
    private func updateProfile(_ update: (inout DLSVisualProfile) -> Void) {
        var value = settings
        update(&value.shared)
        save(value)
    }
    private func save(_ value: DLSVisualPreferences) {
        if let data = try? JSONEncoder().encode(value.simplified()) { visualData = data }
    }
    private func reset() {
        appearance = .system; colorTheme = .standard; fontSize = 14; density = .comfortable
        save(DLSVisualPreferences())
    }
    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { save(try JSONDecoder().decode(DLSVisualPreferences.self, from: Data(contentsOf: url))) }
        catch { importError = "Choose a Edth appearance JSON file. \(error.localizedDescription)" }
    }
    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Edth Appearance.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch { importError = error.localizedDescription }
    }
}
