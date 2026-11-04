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
  var railSize: CGSize = .zero
}
struct NavigationFixtureView: View {
  @Bindable var route: NavigationFixtureState
  var body: some View {
    HStack(spacing: 0) {
      AppSidebar(
        selection: $route.page, didSelect: { if $0.showsHistory { route.history = true } })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { route.railSize = $0 }
      WorkspaceSplitView(historyVisible: $route.history, historyAvailable: (route.page ?? .chat).showsHistory) {
        ChatHistorySidebar(page: $route.page)
      } detail: {
        switch route.page ?? .chat {
        case .chat: ChatView()
        case .registry: RegistryView()
        case .providers: ProvidersView(openChat: { route.page = .chat })
        case .plugins: PluginsView()
        case .skills: SkillsView()
        case .settings: SettingsView()
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
    let project = root.appendingPathComponent("Example Project")
    store.projectFolders = [project]
    store.conversations = (0..<4).map { index in
      ChatConversation(
        id: UUID(), messages: [.init(role: "user", text: "Saved message \(index)")],
        draft: "", usesAgent: false, providerID: store.selectedProviderID,
        workspace: index.isMultiple(of: 2) ? nil : project, updatedAt: .now,
        customTitle: index < 2 ? "Home chat \(index)" : "Archived chat \(index)",
        pinnedAt: index == 2 ? .now : nil, archivedAt: index >= 2 ? .now : nil)
    }
    let archivedID = store.conversations[3].id
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .unifiedCompact
    for appearance in [DLSAppearance.dark, .light] {
      var workspaceToolbarHeight: CGFloat?
      var workspaceRailSize: CGSize?
      window.contentViewController = NSHostingController(
        rootView: NavigationFixtureView(route: route).environment(store).dlsAppearance(appearance))
      for (index, page) in [
        ContentView.Page.plugins, .chat, .providers, .plugins, .settings, .registry, .skills, .plugins, .settings, .providers, .chat,
        .settings, .providers, .chat,
      ].enumerated() {
        print("Opening", page.rawValue)
        fflush(stdout)
        route.page = page
        if page == .chat {
          store.openConversation(archivedID)
          precondition(route.page == .chat, "Opening an archived chat must keep the chat-list context")
        }
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
        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        if let workspaceToolbarHeight {
          precondition(abs(toolbarHeight - workspaceToolbarHeight) < 1,
                       "\(page.rawValue) toolbar height \(toolbarHeight) differs from Plugins height \(workspaceToolbarHeight)")
        } else { workspaceToolbarHeight = toolbarHeight }
        print("Toolbar height:", toolbarHeight)
        precondition(abs(route.railSize.width - ChatLayout.railWidth) < 1)
        if let workspaceRailSize {
          precondition(route.railSize == workspaceRailSize,
                       "\(page.rawValue) changed the navigation rail size")
        } else { workspaceRailSize = route.railSize }
        precondition(Set(identifiers).count == identifiers.count, "Duplicate native toolbar item")
        precondition(identifiers.contains("toggle-history") == page.showsHistory)
        precondition(identifiers.contains("chat-selection") == page.showsHistory)
        precondition(identifiers.contains("settings-sidebar-toggle") == (page == .settings))
        if page.showsHistory,
          let toggle = identifiers.firstIndex(of: "toggle-history"),
          let selection = identifiers.firstIndex(of: "chat-selection") {
          precondition(selection == toggle + 1, "Selector must sit beside the sidebar toggle")
        }
        if page == .providers { precondition(identifiers.contains("providers-search")) }
        if page == .settings {
          precondition(identifiers.contains("settings-sidebar-toggle"))
        }
        if page == .registry { precondition(identifiers.contains("registry-search")) }
        if let view = window.contentView,
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
    for page in [ContentView.Page.registry, .settings, .providers, .chat] {
      route.page = page
      for _ in 0..<10 {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
      precondition(identifiers.contains("toggle-history") == page.showsHistory)
      precondition(identifiers.contains("chat-selection") == page.showsHistory)
    }
    print(
      "Verified page transitions, distinct toolbar searches, and history visibility restoration.")
    window.close()
  }
}
