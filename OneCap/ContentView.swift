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
    enum Page: String, CaseIterable, Identifiable {
        case chat = "Workspace"
        case registry = "Agent Harnesses"
        case providers = "Providers"
        case skills = "Skills"
        case settings = "Settings"
        var id: String { rawValue }
        var showsHistory: Bool { self == .chat }
        var symbol: String {
            switch self {
            case .chat: "house.fill"
            case .registry: "square.stack.3d.up"
            case .providers: "key.horizontal"
            case .skills: "book.closed"
            case .settings: "gearshape"
            }
        }
    }
    var body: some View {
        @Bindable var acp = store.acp
        HStack(spacing: DLSSpacing.none) {
            AppSidebar(selection: $page) { destination in
                if destination.showsHistory { historyVisible = true }
            }
            WorkspaceSplitView(
                historyVisible: $historyVisible, historyAvailable: (page ?? .chat).showsHistory,
                connectionSelected: {
                    page = .chat
                }
            ) {
                ChatHistorySidebar(page: $page, searchRequest: searchRequest)
            } detail: {
                Group {
                    switch page ?? .chat {
                    case .registry: RegistryView()
                    case .providers: ProvidersView(openChat: { page = .chat })
                    case .skills: SkillsView()
                    case .settings: SettingsView()
                    case .chat: ChatView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.background, ignoresSafeAreaEdges: [])
            }
        }
        .padding(.top, DLSSpacing.xxs)
        .padding(.top, ChatLayout.titlebarExtraHeight)
        .frame(minWidth: 900, minHeight: 680)
        .background(theme.colors.surface.ignoresSafeArea())
        .background(WindowFrameAppearance(color: NSColor(theme.colors.surface)))
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            navigate: { destination in
                page = destination
                if destination.showsHistory { historyVisible = true }
            },
            newChat: { page = .chat; store.newChat() },
            search: {
                if !(page ?? .chat).showsHistory { page = .chat }
                historyVisible = true
                searchRequest += 1
            },
            toggleHistory: {
                if !(page ?? .chat).showsHistory {
                    page = .chat
                    historyVisible = true
                } else { historyVisible.toggle() }
            },
            refresh: { Task { await store.refresh() } },
            busy: store.applyingFileUndo || store.savingReviewedFile))
        .environment(\.navigateWorkspace, { page = $0 })
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
