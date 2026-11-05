import AppKit
import Combine
import DLS
import SwiftUI

struct ContentView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var page: Page? = .chat
    @State private var historyVisible = true
    @State private var searchRequest = 0
    private var pageSelection: Binding<Page?> { $page.endingTextEditing() }
    enum Page: String, CaseIterable, Identifiable {
        case chat = "Workspace"
        case registry = "Agent Harnesses"
        case providers = "Providers"
        case plugins = "Plugins"
        case skills = "Skills"
        case settings = "Settings"
        var id: String { rawValue }
        var showsHistory: Bool { self == .chat }
        var iconName: String {
            switch self {
            case .chat: "home"
            case .providers: "keys"
            case .settings: "settings"
            case .registry: "bot"
            case .plugins: "plugins"
            case .skills: "docs"
            }
        }
        var symbol: String {
            switch self {
            case .chat: "house.fill"
            case .registry: "square.stack.3d.up"
            case .providers: "key.horizontal"
            case .plugins: "personalhotspot"
            case .skills: "book.closed"
            case .settings: "gearshape"
            }
        }
    }
    var body: some View {
        @Bindable var acp = store.acp
        HStack(spacing: DLSSpacing.none) {
            AppSidebar(selection: pageSelection) { destination in
                if destination.showsHistory { historyVisible = true }
            }
            WorkspaceSplitView(
                historyVisible: $historyVisible, historyAvailable: (page ?? .chat).showsHistory,
                connectionSelected: {
                    pageSelection.wrappedValue = .chat
                }
            ) {
                ChatHistorySidebar(page: pageSelection, searchRequest: searchRequest)
            } detail: {
                Group {
                    switch page ?? .chat {
                    case .registry: RegistryView()
                    case .providers: ProvidersView(openChat: { pageSelection.wrappedValue = .chat })
                    case .plugins: PluginsView()
                    case .skills: SkillsView()
                    case .settings: SettingsView()
                    case .chat: ChatView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.background, ignoresSafeAreaEdges: [])
                .onAppear { NavigationTrace.mark("page appeared: \(page?.rawValue ?? "Workspace")") }
                .onChange(of: page) { oldPage, newPage in
                    NavigationTrace.mark("page change observed: \(String(describing: oldPage)) -> \(String(describing: newPage))")
                }
            }
        }
        .padding(.top, DLSSpacing.xxs)
        .padding(.top, ChatLayout.titlebarExtraHeight)
        .frame(minWidth: 900, minHeight: 680)
        .background(theme.colors.surface.ignoresSafeArea())
        .background(WindowFrameAppearance(color: NSColor(theme.colors.surface)))
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            navigate: { destination in
                pageSelection.wrappedValue = destination
                if destination.showsHistory { historyVisible = true }
            },
            newChat: { pageSelection.wrappedValue = .chat; store.newChat() },
            search: {
                if !(page ?? .chat).showsHistory { pageSelection.wrappedValue = .chat }
                historyVisible = true
                searchRequest += 1
            },
            toggleHistory: {
                if !(page ?? .chat).showsHistory {
                    pageSelection.wrappedValue = .chat
                    historyVisible = true
                } else { historyVisible.toggle() }
            },
            refresh: { Task { await store.refresh() } },
            busy: store.applyingFileUndo || store.savingReviewedFile))
        .environment(\.navigateWorkspace, { pageSelection.wrappedValue = $0 })
        .focusedSceneValue(\.pluginHost, store)
        .task {
            async let settings: Void = store.load()
            async let catalog: Void = store.loadCatalog()
            _ = await (settings, catalog)
        }
        // Connections belong to the selected conversation, even while a
        // management page is visible. Page navigation must not cancel them.
        .task(id: store.agentConnectionKey) {
            if store.agentConnectionKey != nil { await store.connect() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
            _ in
            store.checkpointConversation(touch: false)
            store.closeChatSessions()
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
        .sheet(item: Binding(get: { store.chatSession.pluginApprover.request }, set: { if $0 == nil { store.chatSession.pluginApprover.resolve(false) } })) { request in
            PluginToolPermissionView(request: request, resolve: store.chatSession.pluginApprover.resolve)
        }
        .sheet(item: Binding(get: { store.pendingPluginCommand }, set: { store.pendingPluginCommand = $0 })) { selection in
            PluginCommandRunView(selection: selection)
        }
        .sheet(item: $acp.permission, onDismiss: { store.acp.resolvePermission(nil) }) { request in
            AgentPermissionView(request: request, resolve: store.acp.resolvePermission)
        }
        .sheet(item: Binding(
            get: { store.terminalLogin.session },
            set: { if $0 == nil { store.terminalLogin.cancel() } })
        ) { session in
            TerminalLoginView(session: session)
                .id(session.id)
        }


    }
}

extension Binding where Value: Equatable {
    /// Resign native editors before SwiftUI replaces the page and its toolbar.
    /// Waiting for onDisappear/onChange leaves AppKit editing a removed control
    /// while it lays out the outgoing toolbar item.
    @MainActor func endingTextEditing(in window: NSWindow? = nil) -> Self {
        Binding(get: { wrappedValue }, set: { [weak window] destination in
            NavigationTrace.mark("selection requested: \(String(describing: wrappedValue)) -> \(String(describing: destination))")
            guard destination != wrappedValue else { return }
            if let window = window ?? NSApp.keyWindow {
                NavigationTrace.mark("BEFORE focus release; responder=\(String(describing: window.firstResponder.map { type(of: $0) }))")
                let released = window.makeFirstResponder(nil)
                NavigationTrace.mark("AFTER focus release; accepted=\(released)")
                guard released else { return }
            } else {
                NavigationTrace.mark("focus release skipped: no key window")
            }
            NavigationTrace.mark("BEFORE selection write")
            wrappedValue = destination
            NavigationTrace.mark("AFTER selection write")
            DispatchQueue.main.async {
                NavigationTrace.mark("next main-queue turn after selection write")
            }
        })
    }
}
