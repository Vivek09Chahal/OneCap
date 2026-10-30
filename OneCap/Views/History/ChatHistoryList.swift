import DLS
import SwiftUI

struct ChatHistoryList: View {
    let conversations: [ChatConversation]
    let projectFolders: [URL]
    let searching: Bool
    let selectedID: UUID?
    let selectedFolder: URL?
    let busy: Bool
    let select: (UUID) -> Void
    let addProject: () -> Void
    let openProject: (URL) -> Void
    let newProjectChat: (URL) -> Void
    let removeProject: (URL) -> Void
    let actions: ChatHistoryActions
    @State private var selectedEntry: HistoryEntryID?
    @State private var archiveExpanded = false

    private var activeConversations: [ChatConversation] { conversations.filter { !$0.isArchived } }
    private var archivedConversations: [ChatConversation] {
        conversations.filter(\.isArchived).sorted { $0.updatedAt > $1.updatedAt }
    }

    // Searching reveals archived matches without changing the user's disclosure preference.
    private var archiveDisclosure: Binding<Bool> {
        Binding(get: { searching || archiveExpanded }, set: { archiveExpanded = $0 })
    }

    private var selection: HistoryEntryID? {
        guard let selectedID, let conversation = conversations.first(where: { $0.id == selectedID }) else {
            return nil
        }
        if conversation.isArchived { return defaultEntry(for: conversation) }
        if let selectedEntry, selectedEntry.conversationID == selectedID {
            if selectedEntry.section == .archive { return defaultEntry(for: conversation) }
            // A pin/archive change can move a row to another section.
            if selectedEntry.section == .pinned && !conversation.isPinned {
                return defaultEntry(for: conversation)
            }
            if selectedEntry.section == .chats && conversation.isPinned {
                return defaultEntry(for: conversation)
            }
            return selectedEntry
        }
        return defaultEntry(for: conversation)
    }

    private func defaultEntry(for conversation: ChatConversation) -> HistoryEntryID {
        let section: HistoryEntryID.Section
        if conversation.isArchived {
            section = .archive
        } else if let folder = conversation.workspace {
            section = .project(folder.standardizedFileURL.path)
        } else {
            section = conversation.isPinned ? .pinned : .chats
        }
        return HistoryEntryID(conversationID: conversation.id, section: section)
    }

    var body: some View {
        List(selection: Binding(get: { selection }, set: { entry in
            if let entry {
                selectedEntry = entry
                select(entry.conversationID)
            }
        })) {
            let pinned = activeConversations.filter(\.isPinned)
            if !pinned.isEmpty {
                Section { rows(pinned, section: .pinned) } header: {
                    HistorySectionHeading("Pinned")
                }
            }
            Section {
                ForEach(activeConversations.historyProjects(in: projectFolders)) { project in
                    HistoryProjectGroup(
                        project: project, searching: searching, selectedEntry: selection,
                        selected: selectedFolder?.standardizedFileURL.path == project.id,
                        open: { openProject(project.folder) },
                        newChat: { newProjectChat(project.folder) },
                        remove: { removeProject(project.folder) }, actions: actions)
                }
            } header: {
                HistorySectionHeading(title: "Projects") {
                    Button("Add project folder", systemImage: "plus", action: addProject)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .padding(.trailing, DLSSpacing.md)
                        .help("Add a project directory")
                }
            }
            Section {
                if activeConversations.historyChats.isEmpty {
                    Text(searching ? "No matching active chats" : "No chats yet")
                        .font(DLSTypography.historyCaption)
                        .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
                        .listRowInsets(HistoryLayout.rowInsets)
                } else {
                    rows(activeConversations.historyChats, section: .chats)
                }
            } header: {
                HistorySectionHeading("Recents")
            }
            Section {
                DisclosureGroup(isExpanded: archiveDisclosure) {
                    if archivedConversations.isEmpty {
                        Text(searching ? "No matching archived chats" : "No archived chats")
                            .font(DLSTypography.historyCaption)
                            .padding(.leading, HistoryLayout.childInset)
                            .listRowInsets(HistoryLayout.rowInsets)
                    } else {
                        rows(archivedConversations, section: .archive)
                    }
                } label: {
                    HStack(spacing: HistoryLayout.itemSpacing) {
                        Image(systemName: "archivebox")
                            .frame(width: DLSSize.iconSmall)
                        Text("Archive")
                    }
                    .font(DLSTypography.historyBody)
                    .frame(minHeight: HistoryLayout.rowHeight)
                }
                .listRowInsets(HistoryLayout.rowInsets)
            }
        }
        .disabled(busy)
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, HistoryLayout.rowHeight)
        .listItemTint(.fixed(.gray))
        .tint(.gray)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        // Prevent layout animations when toggling archive so the sidebar doesn't flicker.
        .animation(.none, value: conversations)
    }
    private func rows(_ conversations: [ChatConversation], section: HistoryEntryID.Section) -> some View {
        ForEach(conversations) { conversation in
            let entry = HistoryEntryID(conversationID: conversation.id, section: section)
            ChatHistoryRow(conversation: conversation, actions: actions, isSelected: selection == entry)
                .tag(entry)
        }
    }
}

/// Identifies one appearance of a conversation, which can occur in multiple sections.
struct HistoryEntryID: Hashable {
    enum Section: Hashable {
        case pinned
        case project(String)
        case chats
        case archive
    }

    let conversationID: UUID
    let section: Section
}
