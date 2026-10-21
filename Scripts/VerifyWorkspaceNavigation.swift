import AppKit
import DLS
import Observation
import SwiftUI

@testable import OneCap

// Compile against the app's Debug module and debug dylib, as with the other UI verification scripts.
// Uses an isolated hidden window and fixture data; never opens the running app or contacts a provider.
@MainActor @Observable final class NavigationFixtureState {
  var page: ContentView.Page? = .chat
  var history = true
  var archive = false
}
struct NavigationFixtureView: View {
  @Bindable var route: NavigationFixtureState
  var body: some View {
    HStack(spacing: 0) {
      AppSidebar(
        selection: $route.page, showingArchive: $route.archive, openArchive: { route.page = .chat })
      WorkspaceSplitView(historyVisible: $route.history, historyAvailable: route.page == .chat) {
        ChatHistorySidebar(page: $route.page, showingArchive: $route.archive)
      } detail: {
        switch route.page ?? .chat {
        case .chat: ChatView()
        case .registry: RegistryView()
        case .providers: ProvidersView(openChat: { route.page = .chat })
        case .skills: SkillsView()
        }
      }
    }.frame(minWidth: 900, minHeight: 680)
  }
}
@main struct VerifyWorkspaceNavigation {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let route = NavigationFixtureState()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-navigation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    store.loaded = true
    store.providers = [
      Provider(name: "DeepSeek", baseURL: "https://api.example.invalid/v1", model: "DeepSeek Chat")
    ]
    store.selectedProviderID = store.providers.first!.id
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .unifiedCompact
    for appearance in [DLSAppearance.dark, .light] {
      window.contentViewController = NSHostingController(
        rootView: NavigationFixtureView(route: route).environment(store).dlsAppearance(appearance))
      for (index, page) in [
        ContentView.Page.chat, .providers, .registry, .skills, .providers, .chat, .providers, .chat,
      ].enumerated() {
        print("Opening", page.rawValue)
        fflush(stdout)
        route.page = page
        for _ in 0..<15 {
          window.contentView?.superview?.layoutSubtreeIfNeeded()
          if let view = window.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
          {
            view.cacheDisplay(in: view.bounds, to: bitmap)
          }
          try await Task.sleep(for: .milliseconds(30))
        }
        let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
        precondition(Set(identifiers).count == identifiers.count, "Duplicate native toolbar item")
        precondition(identifiers.contains("toggle-history") == (page == .chat))
        precondition(identifiers.contains("chat-selection") == (page == .chat))
        if page == .chat,
          let toggle = identifiers.firstIndex(of: "toggle-history"),
          let selection = identifiers.firstIndex(of: "chat-selection") {
          precondition(selection == toggle + 1, "Selector must sit beside the sidebar toggle")
        }
        if page == .providers { precondition(identifiers.contains("providers-search")) }
        if page == .registry { precondition(identifiers.contains("registry-search")) }
        if page != .chat, let view = window.contentView,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        {
          view.cacheDisplay(in: view.bounds, to: bitmap)
          try bitmap.representation(using: .png, properties: [:])?.write(
            to: URL(fileURLWithPath: "/tmp/OneCap-navigation-\(appearance)-\(index).png"))
        }
        print("Verified", appearance, page.rawValue)
      }
    }
    // A manually hidden history panel stays hidden when returning from management pages.
    route.history = false
    for page in [ContentView.Page.registry, .providers, .chat] {
      route.page = page
      for _ in 0..<10 {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
      precondition(identifiers.contains("toggle-history") == (page == .chat))
      precondition(identifiers.contains("chat-selection") == (page == .chat))
    }
    print(
      "Verified page transitions, distinct toolbar searches, and history visibility restoration.")
    window.close()
  }
}
