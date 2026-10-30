import AppKit
import DLS
import SwiftUI

@main struct OneCapApp: App {
    @AppStorage("appearance") private var appearance: DLSAppearance = .system
    @State private var windows = ChatWindows()

    var body: some Scene {
        WindowGroup("Workspace", id: "workspace", for: UUID.self) { $windowID in
            ChatWindowRoot(windows: windows, windowID: $windowID)
                .dlsAppearance(appearance)
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands { WorkspaceCommands() }
    }
}

/// Retain stores for background replies and route a conversation to its existing window.
@MainActor @Observable final class ChatWindows {
    let shared = AppStore()
    var stores: [UUID: AppStore] = [:]
    var pendingChats: [UUID: UUID] = [:]
    private var loading: Task<Void, Never>?

    func store(for id: UUID) async -> AppStore {
        if loading == nil {
            loading = Task { await shared.load() }
        }
        await loading?.value
        if let store = stores[id] { return store }
        let store = shared.makeWindowStore()
        stores[id] = store
        if let chat = pendingChats.removeValue(forKey: id) { store.openConversation(chat) }
        return store
    }

    func owner(of chat: UUID, excluding id: UUID) -> UUID? {
        stores.first { $0.key != id && $0.value.conversationID == chat }?.key
    }
}

private struct ChatWindowRoot: View {
    let windows: ChatWindows
    @Binding var windowID: UUID?
    @State private var generatedID = UUID()
    @State private var store: AppStore?
    @Environment(\.openWindow) private var openWindow
    private var id: UUID { windowID ?? generatedID }

    var body: some View {
        Group {
            if let store {
                ContentView()
                    .environment(store)
                    .environment(\.selectChat, { chat in
                        if let owner = windows.owner(of: chat, excluding: id) {
                            openWindow(id: "workspace", value: owner)
                        } else { store.openConversation(chat) }
                    })
                    .environment(\.openChatWindow, { chat in
                        store.checkpointConversation(touch: false)
                        if let owner = windows.owner(of: chat, excluding: id) {
                            openWindow(id: "workspace", value: owner)
                        } else {
                            if store.conversationID == chat { store.newChat() }
                            let target = UUID()
                            windows.pendingChats[target] = chat
                            openWindow(id: "workspace", value: target)
                        }
                    })
            } else { ProgressView("Loading workspace…").frame(minWidth: 900, minHeight: 680) }
        }
        .task {
            let stableID = id
            if windowID == nil { windowID = stableID }
            store = await windows.store(for: stableID)
        }
        .onDisappear { store?.checkpointConversation(touch: false) }
    }
}

private struct SelectChatKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (UUID) -> Void = { _ in }
}
private struct OpenChatWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (UUID) -> Void = { _ in }
}
extension EnvironmentValues {
    var selectChat: @MainActor @Sendable (UUID) -> Void {
        get { self[SelectChatKey.self] }
        set { self[SelectChatKey.self] = newValue }
    }
    var openChatWindow: @MainActor @Sendable (UUID) -> Void {
        get { self[OpenChatWindowKey.self] }
        set { self[OpenChatWindowKey.self] = newValue }
    }
}

struct WorkspaceActions {
    var navigate: (ContentView.Page) -> Void
    var newChat: () -> Void
    var search: () -> Void
    var toggleHistory: () -> Void
    var refresh: () -> Void
    var busy: Bool
}
private struct WorkspaceActionsKey: FocusedValueKey { typealias Value = WorkspaceActions }
extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

private struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.navigate(.settings) }
                .keyboardShortcut(",", modifiers: .command).disabled(actions == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { actions?.newChat() }
                .keyboardShortcut("n").disabled(actions == nil || actions?.busy == true)
            Button("New Window") { openWindow(id: "workspace", value: UUID()) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find Chats") { actions?.search() }
                .keyboardShortcut("f").disabled(actions == nil)
        }
        CommandGroup(before: .toolbar) {
            ForEach(Array(ContentView.Page.allCases.enumerated()), id: \.element.id) { index, page in
                Button(page.rawValue) { actions?.navigate(page) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(actions == nil)
            }
            Divider()
            Button("Toggle History") { actions?.toggleHistory() }
                .keyboardShortcut("s", modifiers: [.command, .control]).disabled(actions == nil)
            Button("Refresh Agent Harnesses") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(actions == nil)
        }
        CommandGroup(after: .windowArrangement) {
            Button("New Window") { openWindow(id: "workspace", value: UUID()) }
        }
    }
}
