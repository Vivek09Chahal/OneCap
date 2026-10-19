import DLS
import SwiftUI

struct ChatHistorySidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var page: ContentView.Page?
    @State private var query = ""
    @State private var searching = false
    @State private var showingArchive = false
    @FocusState private var searchFocused: Bool
    
    private var filtered: [ChatConversation] {
        store.conversations.filter {
            $0.isArchived == showingArchive
            && $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    private var visibleFolders: [URL] {
        guard !showingArchive else { return [] }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.projectFolders.filter { query.isEmpty || $0.path.localizedStandardContains(query) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            HStack {
                Menu {
                    Button("All chats", systemImage: "bubble.left.and.bubble.right") {
                        showingArchive = false
                    }
                    Button("Archived chats", systemImage: "archivebox") { showingArchive = true }
                } label: {
                    HStack(spacing: DLSSpacing.sm) {
                        Text(showingArchive ? "Archive" : "OneCap").font(DLSTypography.historyTitle)
                        Image(systemName: "chevron.down").font(DLSTypography.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Chat history options")
                Spacer()
                Button("Search chats", systemImage: searching ? "xmark" : "magnifyingglass") {
                    searching.toggle()
                    if !searching { query = "" }
                    searchFocused = searching
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.textSecondary)
                .help(searching ? "Close search" : "Search chats")
            }
            .padding(.horizontal, DLSSpacing.lg)
            .padding(.top, DLSSpacing.lg)
            .padding(.bottom, DLSSpacing.sm)
            
            if searching {
                HStack(spacing: DLSSpacing.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.colors.textSecondary)
                    TextField("Search chats", text: $query).textFieldStyle(.plain).focused($searchFocused)
                }
                .padding(DLSSpacing.sm)
                .background(theme.colors.background, in: RoundedRectangle(cornerRadius: DLSRadius.small))
                .padding(.horizontal, DLSSpacing.md)
            }
            
            if filtered.isEmpty && (showingArchive || !query.isEmpty) && visibleFolders.isEmpty {
                HistoryEmptyState(searching: !query.isEmpty, archived: showingArchive)
            } else {
                ChatHistoryList(
                    conversations: filtered, projectFolders: visibleFolders,
                    selectedID: page == .chat ? store.conversationID : nil,
                    selectedFolder: store.workspace,
                    busy: store.sending,
                    select: { id in
                        store.openConversation(id)
                        page = .chat
                    },
                    addProject: addProject,
                    openProject: { folder in
                        store.openProject(folder)
                        page = .chat
                    },
                    newProjectChat: { folder in
                        store.newProjectChat(in: folder)
                        page = .chat
                    },
                    actions: ChatHistoryActions(
                        rename: store.renameConversation, togglePin: store.toggleConversationPin,
                        toggleArchive: store.toggleConversationArchive, delete: store.deleteConversation))
            }
        }
        .foregroundStyle(theme.colors.textPrimary)
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.colors.borderStrong)
                .frame(width: DLSSize.border)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
    private func addProject() {
        Task {
            if let folder = await WorkspaceFolderPicker.choose(), !store.sending {
                store.openProject(folder)
                showingArchive = false
                page = .chat
            }
        }
    }
    
}

private struct HistoryEmptyState: View {
    @Environment(\.dlsTheme) private var theme
    let searching: Bool
    let archived: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
            Text(searching ? "No matching chats" : archived ? "No archived chats" : "Recents").font(
                DLSTypography.historySection)
            Text(
                searching
                ? "Try another search."
                : archived
                ? "Archived conversations will appear here." : "Your conversations will appear here."
            )
            .font(DLSTypography.historyBody)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .padding(DLSSpacing.lg)
        Spacer()
    }
}
