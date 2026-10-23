import DLS
import SwiftUI

struct ChatHistorySidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Binding var page: ContentView.Page?
    @State private var query = ""
    @State private var searching = false
    let showingArchive: Bool
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
        VStack(alignment: .leading, spacing: HistoryLayout.itemSpacing) {
            HStack {
                Group {
                    if store.chatUsesAgent { ChatAgentPicker() } else { ChatProviderPicker() }
                }
                // Match the native list headings; menu labels already include a four-point inset.
                .padding(.leading, DLSSpacing.xxs)
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
            .padding(.horizontal, HistoryLayout.horizontalInset)
            .padding(.top, DLSSpacing.md)
            .padding(.bottom, DLSSpacing.xs)

            Button {
                page = .chat
                store.newChat()
            } label: {
                HStack(spacing: HistoryLayout.itemSpacing) {
                    Image(systemName: "square.and.pencil")
                        .frame(width: DLSSize.iconSmall)
                    Text("New chat")
                }
                    .font(DLSTypography.historyBody).fontWeight(.regular)
                    // The fixed icon column centers this narrower symbol by two points.
                    .padding(.leading, DLSSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: HistoryLayout.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.applyingFileUndo || store.savingReviewedFile)
            .keyboardShortcut("n", modifiers: .command)
            .help("Start a new chat")
            .padding(.horizontal, HistoryLayout.horizontalInset)

            if showingArchive {
                Text("Archived chats")
                    .font(DLSTypography.historySection)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, DLSSpacing.lg)
            }
            
            if searching {
                HStack(spacing: DLSSpacing.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.colors.textSecondary)
                    TextField("Search chats", text: $query).textFieldStyle(.plain).focused($searchFocused)
                        .font(DLSTypography.historyBody)
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
                    showingArchive: showingArchive,
                    selectedID: (page ?? .chat).showsHistory ? store.conversationID : nil,
                    selectedFolder: store.workspace,
                    busy: store.applyingFileUndo || store.savingReviewedFile,
                    select: { id in
                        store.openConversation(id)
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
                    removeProject: store.removeProject,
                    actions: ChatHistoryActions(
                        rename: store.renameConversation, togglePin: store.toggleConversationPin,
                        toggleArchive: store.toggleConversationArchive, delete: store.deleteConversation))
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .fontDesign(.default)
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
            if let folder = await WorkspaceFolderPicker.choose() {
                store.openProject(folder)
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
            Text(searching ? "No matching chats" : archived ? "No archived chats" : "Chats").font(
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
