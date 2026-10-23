import DLS
import SwiftUI

@main struct OneCapApp: App {
    @AppStorage("appearance") private var appearance: DLSAppearance = .system
    @State private var store = AppStore()
    @FocusedValue(\.openSettings) private var openSettings
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).dlsAppearance(appearance)
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openSettings?() }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(openSettings == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Agent Harnesses") { Task { await store.refresh() } }.keyboardShortcut(
                    "r", modifiers: [.command, .shift])
            }
        }
    }
}

private struct OpenSettingsKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openSettings: (() -> Void)? {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}
