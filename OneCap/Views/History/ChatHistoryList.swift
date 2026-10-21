import DLS
import SwiftUI

struct ChatHistoryList: View {
    let conversations: [ChatConversation]
    let projectFolders: [URL]
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

    private var selection: HistoryEntryID? {
        guard let selectedID, let conversation = conversations.first(where: { $0.id == selectedID }) else {
            return nil
        }
        if let selectedEntry, selectedEntry.conversationID == selectedID {
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
        if let folder = conversation.workspace {
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
            let pinned = conversations.filter(\.isPinned)
            if !pinned.isEmpty {
                Section { rows(pinned, section: .pinned) } header: {
                    HistorySectionHeading("Pinned")
                }
            }
            Section {
                if conversations.historyChats.isEmpty {
                    Text("No chats yet")
                        .font(DLSTypography.historyCaption)
                        .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
                        .listRowInsets(HistoryLayout.rowInsets)
                } else {
                    rows(conversations.historyChats, section: .chats)
                }
            } header: {
                HistorySectionHeading("Chats")
            }
            Section {
                ForEach(conversations.historyProjects(in: projectFolders)) { project in
                    HistoryProjectGroup(
                        project: project, selectedEntry: selection,
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
        }
        .disabled(busy)
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, HistoryLayout.rowHeight)
        .listItemTint(.fixed(.gray))
        .tint(.gray)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
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
    }

    let conversationID: UUID
    let section: Section
}
