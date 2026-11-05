import AppKit
import DLS
import Observation
import SwiftUI

@testable import OneCap

// Compile against the app's Debug module and debug dylib, as with the other UI verification scripts.
// Uses an isolated window and fixture data; never opens the running app or contacts a provider.
@MainActor @Observable final class NavigationFixtureState {
  var page: ContentView.Page? = .chat
  var history = true
  var railSize: CGSize = .zero
  @ObservationIgnored weak var window: NSWindow?
  var selection: Binding<ContentView.Page?> {
    Binding(get: { self.page }, set: { self.page = $0 }).endingTextEditing(in: window)
  }
}
struct NavigationFixtureView: View {
  @Bindable var route: NavigationFixtureState
  var body: some View {
    HStack(spacing: 0) {
      AppSidebar(
        selection: route.selection, didSelect: { if $0.showsHistory { route.history = true } })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { route.railSize = $0 }
      WorkspaceSplitView(historyVisible: $route.history, historyAvailable: (route.page ?? .chat).showsHistory) {
        ChatHistorySidebar(page: route.selection)
      } detail: {
        switch route.page ?? .chat {
        case .chat: ChatView()
        case .registry: RegistryView()
        case .providers: ProvidersView(openChat: { route.selection.wrappedValue = .chat })
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
    let rapid = CommandLine.arguments.contains("--rapid")
    NSApp.setActivationPolicy(rapid ? .regular : .prohibited)
    NSSetUncaughtExceptionHandler { exception in
      fputs("Uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "unknown")\n", stderr)
    }
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
    route.window = window
    if rapid {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    var workspaceToolbar: NSToolbar?
    for appearance in [DLSAppearance.dark, .light] {
      var workspaceToolbarHeight: CGFloat?
      var workspaceRailSize: CGSize?
      window.contentViewController = NSHostingController(
        rootView: NavigationFixtureView(route: route).environment(store).dlsAppearance(appearance))
      // Replacing the whole hosting controller creates a new toolbar. Only
      // navigation within that controller must retain its toolbar instance.
      workspaceToolbar = nil
      for _ in 0..<15 {
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      for (index, page) in [
        ContentView.Page.plugins, .chat, .providers, .plugins, .settings, .registry, .skills, .plugins, .settings, .providers, .chat,
        .settings, .providers, .chat,
      ].enumerated() {
        print("Opening", page.rawValue)
        fflush(stdout)
        // Enter real AppKit editing before replacing the page/toolbar. Hidden
        // window navigation alone does not cover the shared field editor.
        let views = (window.contentView.map { descendants($0) } ?? [])
          + (window.toolbar?.items.compactMap(\.view).flatMap { descendants($0) } ?? [])
        var edited = false
        if route.page == .chat,
          let editor = views.compactMap({ $0 as? NSTextView }).first(where: {
            $0.isEditable && $0.accessibilityLabel() == "Message"
          }) {
          precondition(window.makeFirstResponder(editor))
          editor.insertText("Draft before navigation", replacementRange: NSRange(location: NSNotFound, length: 0))
          edited = true
        } else if let field = views.first(where: { $0 is NSSearchField }) as? NSSearchField {
          precondition(window.makeFirstResponder(field))
          precondition(field.currentEditor() != nil)
          (field.currentEditor() as? NSTextView)?.insertText("test", replacementRange: NSRange(location: NSNotFound, length: 0))
          edited = true
        } else if let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.isEnabled }) {
          precondition(window.makeFirstResponder(field))
          precondition(field.currentEditor() != nil)
          edited = true
        } else if let editor = views.compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable }) {
          precondition(window.makeFirstResponder(editor))
          editor.insertText("Draft before navigation", replacementRange: NSRange(location: NSNotFound, length: 0))
          edited = true
        }
        if !rapid { try await Task.sleep(for: .milliseconds(30)) }
        let draft = store.draft
        let changingPage = route.page != page
        if rapid {
          clickPage(page, in: window)
          precondition(route.page == page, "Sidebar click must navigate")
        } else {
          route.selection.wrappedValue = page
        }
        if edited && changingPage {
          precondition(!(window.firstResponder is NSTextView), "Navigation must resign editing before replacing views")
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
        verifyToolbar(in: window, retainedToolbar: &workspaceToolbar)
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
        precondition(store.draft == draft, "Navigation must preserve the typed draft")
        if page == .chat {
          store.openConversation(archivedID)
          precondition(route.page == .chat, "Opening an archived chat must keep the chat-list context")
        }
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
    if rapid {
      for iteration in 0..<200 {
        let page = ContentView.Page.allCases[iteration % ContentView.Page.allCases.count]
        let views = (window.contentView.map { descendants($0) } ?? [])
          + (window.toolbar?.items.compactMap(\.view).flatMap { descendants($0) } ?? [])
        if let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.isEnabled }) {
          _ = window.makeFirstResponder(field)
        } else if let editor = views.compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable }) {
          _ = window.makeFirstResponder(editor)
        }
        // Let the focus callback start its animation, then replace the page
        // while that animation is still running.
        try await Task.sleep(for: .milliseconds(5))
        clickPage(page, in: window)
        precondition(route.page == page, "Rapid sidebar click must navigate")
        // Exercise toolbar measurement during navigation, including long titles
        // at narrow widths. Title sizing must not feed layout back into state.
        if let index = store.conversations.firstIndex(where: { $0.id == store.conversationID }) {
          store.conversations[index].customTitle = iteration.isMultiple(of: 2)
            ? String(repeating: "Long conversation title ", count: 12) : "Short title"
        }
        window.setContentSize(NSSize(width: iteration.isMultiple(of: 2) ? 900 : 1380, height: 780))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        verifyToolbar(in: window, retainedToolbar: &workspaceToolbar)
        try await Task.sleep(for: .milliseconds(5))
      }
      print("Verified 200 rapid focus/navigation transitions with resizing and changing titles")
    }
    // A manually hidden history panel stays hidden when returning from management pages.
    route.history = false
    for page in [ContentView.Page.registry, .settings, .providers, .chat] {
      route.selection.wrappedValue = page
      for _ in 0..<10 {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
      precondition(identifiers.contains("toggle-history") == page.showsHistory)
      precondition(identifiers.contains("chat-selection") == page.showsHistory)
    }
    print(
      "Verified focused-editor page transitions, draft preservation, distinct toolbar searches, and history visibility restoration.")
    window.close()
  }

  @MainActor static func verifyToolbar(in window: NSWindow, retainedToolbar: inout NSToolbar?) {
    guard let toolbar = window.toolbar else { preconditionFailure("Missing workspace toolbar") }
    if let retainedToolbar {
      precondition(toolbar === retainedToolbar, "Navigation must retain the window toolbar")
    } else { retainedToolbar = toolbar }
    precondition(!toolbar.allowsUserCustomization, "Pages must not install a separate customizable toolbar")
    for item in toolbar.items {
      guard let view = item.view else { continue }
      let size = view.fittingSize
      precondition(size.width.isFinite && size.height.isFinite,
                   "Non-finite toolbar size for \(item.itemIdentifier.rawValue)")
      if item.itemIdentifier.rawValue == "conversation-title" {
        precondition(abs(size.width - 280) < 1, "Conversation title must retain a fixed width")
      }
    }
  }

  @MainActor static func clickPage(_ page: ContentView.Page, in window: NSWindow) {
    guard let content = window.contentView else { preconditionFailure("Missing content") }
    // Match AppSidebar's fixed rail layout; send real mouse events rather than
    // setting the binding (SwiftUI buttons are virtual accessibility elements).
    let y: CGFloat
    switch page {
    case .settings: y = DLSSpacing.md + DLSSize.avatar / 2
    case .skills: y = DLSSpacing.md + DLSSize.avatar * 1.5 + DLSSpacing.lg
    default:
      let index = ContentView.Page.allCases.filter { $0 != .skills && $0 != .settings }.firstIndex(of: page)!
      y = window.contentLayoutRect.height - DLSSpacing.md - DLSSize.avatar / 2
        - CGFloat(index) * (DLSSize.avatar + DLSSpacing.sm)
    }
    let localY = content.isFlipped ? content.bounds.maxY - y : y
    let point = content.convert(NSPoint(x: ChatLayout.railWidth / 2, y: localY), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
      NSApp.sendEvent(event)
    }
  }

  @MainActor static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
