import DLS
import SwiftUI

struct ChatHistorySidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.selectChat) private var selectChat
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dlsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var page: ContentView.Page?
    @State private var query = ""
    @State private var showingSearch = false
    @State private var searchFocusRequest = 0
    var searchRequest = 0
    
    private var filtered: [ChatConversation] {
        store.conversations.filter {
            $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    private var visibleFolders: [URL] {
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
                Spacer(minLength: DLSSpacing.sm)
                Button {
                    showingSearch.toggle()
                    if showingSearch { searchFocusRequest += 1 }
                    else { query = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(DLSTypography.historyBody)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: DLSSize.toolbarButton, height: DLSSize.toolbarButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showingSearch ? "Hide chat search" : "Search chats")
                .accessibilityLabel(showingSearch ? "Hide chat search" : "Search chats")
                .accessibilityValue(showingSearch ? "Expanded" : "Collapsed")
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
                        .imageScale(.small)
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
            .help("Start a new chat")
            .padding(.horizontal, HistoryLayout.horizontalInset)

            if showingSearch {
                ToolbarSearchField(text: $query, prompt: "Search chats", focusRequest: searchFocusRequest)
                    .frame(height: 32)
                    .padding(.horizontal, DLSSpacing.md)
                    .padding(.vertical, DLSSpacing.xs)
            }

            ChatHistoryList(
                conversations: filtered, projectFolders: visibleFolders,
                searching: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedID: (page ?? .chat).showsHistory ? store.conversationID : nil,
                selectedFolder: store.workspace,
                busy: store.applyingFileUndo || store.savingReviewedFile,
                select: { id in
                    selectChat(id)
                },
                addProject: addProject,
                openProject: { folder in
                    if let latest = store.conversations.filter({
                        !$0.isArchived && $0.workspace?.standardizedFileURL == folder.standardizedFileURL
                    }).max(by: { $0.updatedAt < $1.updatedAt }) {
                        selectChat(latest.id)
                    } else { store.openProject(folder) }
                    page = .chat
                },
                newProjectChat: { folder in
                    store.newProjectChat(in: folder)
                    page = .chat
                },
                removeProject: store.removeProject,
                actions: ChatHistoryActions(
                    rename: store.renameConversation, togglePin: store.toggleConversationPin,
                    toggleArchive: { id in
                        toggleArchive(id)
                    }, delete: store.deleteConversation))
        }
        .foregroundStyle(colorScheme == .dark ? Color.white : theme.colors.textPrimary)
        .onChange(of: searchRequest) { _, _ in
            showingSearch = true
            searchFocusRequest += 1
        }
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
    private func toggleArchive(_ id: UUID) {
        guard let before = store.conversations.first(where: { $0.id == id })?.isArchived else { return }
        store.toggleConversationArchive(id)
        guard store.conversations.first(where: { $0.id == id })?.isArchived != before else { return }
        undoManager?.registerUndo(withTarget: store) { _ in
            MainActor.assumeIsolated { toggleArchive(id) }
        }
        undoManager?.setActionName(before ? "Restore Chat" : "Archive Chat")
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
