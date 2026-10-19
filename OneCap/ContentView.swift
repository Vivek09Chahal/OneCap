import AppKit
import Combine
import DLS
import SwiftUI

struct ContentView: View {
    @Environment(\.dlsTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var page: Page? = .chat
    @State private var historyVisible = true
    enum Page: String, CaseIterable, Identifiable {
        case chat = "Workspace"
        case registry = "Agent Registry"
        case providers = "Providers"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .chat: "house.fill"
            case .registry: "square.stack.3d.up"
            case .providers: "key.horizontal"
            }
        }
    }
    var body: some View {
        @Bindable var acp = store.acp
        HStack(spacing: DLSSpacing.none) {
            AppSidebar(selection: $page)
            WorkspaceSplitView(historyVisible: $historyVisible) {
                ChatHistorySidebar(page: $page)
            } detail: {
                Group {
                    switch page ?? .chat {
                    case .registry: RegistryView()
                    case .providers: ProvidersView(openChat: { page = .chat })
                    case .chat: ChatView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.background, ignoresSafeAreaEdges: [])
            }
        }
        .padding(.top, DLSSpacing.xxs)
        .padding(.top, ChatLayout.titlebarExtraHeight)
        .frame(minWidth: 980, minHeight: 680)
        .background(theme.colors.surface.ignoresSafeArea())
        .background(WindowFrameAppearance(color: NSColor(theme.colors.surface)))
        .task {
            async let settings: Void = store.load()
            async let catalog: Void = store.refresh()
            _ = await (settings, catalog)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
            _ in
            store.checkpointConversation(touch: false)
            store.terminalLogin.cancel()
            store.acp.close()
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
