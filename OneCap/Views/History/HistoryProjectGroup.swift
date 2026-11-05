import DLS
import SwiftUI

struct HistoryProjectGroup: View {
    @Environment(\.dlsTheme) private var theme
    let project: ChatHistoryProject
    var browsingArchive = false
    var searching = false
    let selectedEntry: HistoryEntryID?
    let selected: Bool
    let open: () -> Void
    let newChat: () -> Void
    let remove: () -> Void
    let actions: ChatHistoryActions
    @State private var expanded = true
    @State private var showingAllChats = false
    @State private var confirmingRemoval = false

    private let initialChatCount = 5

    private var visibleConversations: [ChatConversation] {
        if searching || showingAllChats { return project.conversations }
        return Array(project.conversations.prefix(initialChatCount))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if project.conversations.isEmpty {
                Text("No chats yet").dlsFont(.historyCaption)
                    .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
                    .padding(.leading, HistoryLayout.childInset)
                    .listRowInsets(HistoryLayout.rowInsets)
            }
            ForEach(visibleConversations) { conversation in
                let entry = HistoryEntryID(conversationID: conversation.id, section: .project(project.id))
                ChatHistoryRow(conversation: conversation, actions: actions, isSelected: selectedEntry == entry)
                    .padding(.leading, HistoryLayout.childInset)
                    .tag(entry)
            }
            if !searching && project.conversations.count > initialChatCount {
                Button {
                    showingAllChats.toggle()
                } label: {
                    Label {
                        Text(showingAllChats ? "Show less" : "Show more")
                    } icon: {
                        Image(systemName: showingAllChats ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                        .dlsFont(.historyCaption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: HistoryLayout.rowHeight, alignment: .leading)
                .padding(.leading, HistoryLayout.childInset)
                .listRowInsets(HistoryLayout.rowInsets)
                .accessibilityLabel(showingAllChats
                    ? "Show fewer chats in \(project.folder.lastPathComponent)"
                    : "Show all chats in \(project.folder.lastPathComponent)")
                .accessibilityValue(showingAllChats ? "Expanded" : "Collapsed")
            }
        } label: {
            HStack(spacing: HistoryLayout.itemSpacing) {
                if browsingArchive {
                    projectLabel
                } else {
                    Button(action: open) {
                        projectLabel
                    }
                    .buttonStyle(.plain)
                    .help(project.folder.path)
                    Button(action: startChat) {
                        HistoryActionIcon("edit")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New chat in \(project.folder.lastPathComponent)")
                    .help("New chat in this project")
                }
            }
            .frame(minHeight: HistoryLayout.rowHeight)
            .contextMenu {
                if !browsingArchive {
                    Button(action: startChat) {
                        Label { Text("New chat in project") } icon: { AppIcon("edit") }
                    }
                    Divider()
                    Button("Remove project", systemImage: "trash", role: .destructive) {
                        confirmingRemoval = true
                    }
                }
            }
        }
        .listRowInsets(HistoryLayout.projectRowInsets)
        .alert("Remove \(project.folder.lastPathComponent)?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("This permanently removes the project and all its saved chats from Edth on this Mac. The folder and its files stay on disk.")
        }
        .onChange(of: selected) { _, selected in
            if selected { expanded = true }
        }
        .onChange(of: selectedEntry, initial: true) { _, entry in
            guard let entry, entry.section == .project(project.id),
                  let index = project.conversations.firstIndex(where: { $0.id == entry.conversationID })
            else { return }
            expanded = true
            if index >= initialChatCount {
                showingAllChats = true
            }
        }
    }
    private var projectLabel: some View {
        HStack(spacing: HistoryLayout.itemSpacing) {
            Image(systemName: "folder")
                .imageScale(.small)
                .frame(width: DLSSize.iconSmall)
            Text(project.folder.lastPathComponent).lineLimit(1)
        }
        .dlsFont(.historyBody).fontWeight(.regular)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func startChat() {
        expanded = true
        newChat()
    }
}
