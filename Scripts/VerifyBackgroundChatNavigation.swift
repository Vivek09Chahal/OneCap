import AppKit
import DLS
import Observation
import SwiftUI

@testable import OneCap

private struct NavigationInstaller: AgentInstalling {
    func catalog() async throws -> Registry { Registry(version: "1", agents: []) }
    func install(_ agent: Agent) async throws -> InstalledAgent { throw AppFailure("Not used") }
    func uninstall(_ agent: InstalledAgent, repository: AppRepository) async throws -> AgentUninstallResult {
        throw AppFailure("Not used")
    }
}

@MainActor @Observable private final class BackgroundNavigationRoute {
    var showingChat = true
}

private struct BackgroundNavigationView: View {
    @Environment(AppStore.self) private var store
    let route: BackgroundNavigationRoute

    var body: some View {
        NavigationStack {
            if route.showingChat { ChatView() }
            else { SettingsView() }
        }
        // Match ContentView: the owner survives changes to the visible page.
        .task(id: store.agentConnectionKey) {
            if store.agentConnectionKey != nil { await store.connect() }
        }
    }
}

// Compile against the app's Debug module and debug dylib. Uses an isolated
// hosting window and local ACP fixture; never contacts a real agent or provider.
@main
struct VerifyBackgroundChatNavigation {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-background-navigation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("agent.py")
        try #"""
        import json, pathlib, sys, time
        root = pathlib.Path(sys.argv[1])
        def send(obj):
            print(json.dumps(dict(jsonrpc='2.0', **obj)), flush=True)
        def wait_for(name):
            while not (root / name).exists():
                time.sleep(0.01)
        def chunk(text):
            send(dict(method='session/update', params=dict(sessionId='fixture', update=dict(sessionUpdate='agent_message_chunk', content=dict(type='text', text=text)))))
        for line in sys.stdin:
            m = json.loads(line)
            method = m.get('method')
            if method == 'initialize':
                (root / 'connecting').touch()
                wait_for('allow-connect')
                send(dict(id=m['id'], result=dict(protocolVersion=1)))
            elif method == 'session/new':
                send(dict(id=m['id'], result=dict(sessionId='fixture')))
            elif method == 'session/prompt':
                chunk('Working in background. ')
                wait_for('allow-completion')
                chunk('Navigation completion verified.')
                send(dict(id=m['id'], result=dict(stopReason='end_turn')))
        """#.write(to: script, atomically: true, encoding: .utf8)
        let route = BackgroundNavigationRoute()
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"), installer: NavigationInstaller())
        store.loaded = true
        store.skillsLoaded = true
        store.installed = [.init(id: "fixture", name: "Fixture", version: "1", executable: "/usr/bin/python3",
                                 arguments: ["-u", script.path, root.path], environment: [:], directory: root.path)]
        store.selectedAgentID = "fixture"
        store.chatUsesAgent = true
        store.workspace = root
        defer { store.closeChatSessions() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: BackgroundNavigationView(route: route).environment(store).dlsAppearance(.dark))
        defer { window.close() }

        try await wait(window) { FileManager.default.fileExists(atPath: root.appendingPathComponent("connecting").path) }
        route.showingChat = false
        try await wait(window) { window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "settings-sidebar-toggle" } == true }
        try Data().write(to: root.appendingPathComponent("allow-connect"))
        print("Waiting for connection while Settings is visible.")
        fflush(stdout)
        try await wait(window) { store.acp.sessionReady && !store.connecting }
        precondition(store.connectionError == nil, "Leaving Workspace must not cancel its connection")
        print("Connection completed while Settings was visible.")

        route.showingChat = true
        try await wait(window) { window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "reload-agent" } == true }
        precondition(store.send("Complete while away", useAgent: true))
        try await wait(window) { store.messages.last?.text == "Working in background. " }
        route.showingChat = false
        try await wait(window) { window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "settings-sidebar-toggle" } == true }
        try Data().write(to: root.appendingPathComponent("allow-completion"))
        try await wait(window) { !store.sending }
        precondition(store.messages.last?.replyState == .completed)
        route.showingChat = true
        try await wait(window) { window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "reload-agent" } == true }
        precondition(store.messages.last?.text == "Working in background. Navigation completion verified.")
        precondition(store.acp.sessionReady && store.connectionError == nil)
        print("Completed reply is visible immediately on return, without refresh.")
    }

    @MainActor private static func wait(_ window: NSWindow, until condition: () -> Bool) async throws {
        for _ in 0..<300 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw AppFailure("Timed out waiting for navigation or background work")
    }
}
