import DLS
import SwiftUI

@main struct OneCapApp: App {
    @AppStorage("appearance") private var appearance: DLSAppearance = .system
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).dlsAppearance(appearance)
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Agent Harnesses") { Task { await store.refresh() } }.keyboardShortcut(
                    "r", modifiers: [.command, .shift])
            }
        }
        Settings {
            AppearanceSettingsView(appearance: $appearance).dlsAppearance(appearance)
        }
    }
}
