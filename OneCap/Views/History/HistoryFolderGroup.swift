import DLS
import SwiftUI

struct HistoryFolderGroup: View {
    @Environment(\.dlsTheme) private var theme
    let folder: ChatHistoryFolder
    let searching: Bool
    let selectedID: UUID?
    let select: (UUID) -> Void
    let newChat: (ChatFolder) -> Void
    let rename: (ChatFolder, String) -> Void
    let delete: (ChatFolder) -> Void
    let actions: ChatHistoryActions
    @State private var expanded = false
    @State private var showingAllChats = false
    @State private var confirmingRemoval = false
    @State private var renaming = false
    @State private var renameDraft = ""

    private let initialChatCount = 5

    private var visibleConversations: [ChatConversation] {
        if searching || showingAllChats { return folder.conversations }
        return Array(folder.conversations.prefix(initialChatCount))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if folder.conversations.isEmpty {
                Text("No chats yet").dlsFont(.historyCaption)
                    .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
                    .padding(.leading, HistoryLayout.childInset)
                    .listRowInsets(HistoryLayout.rowInsets)
            }
            ForEach(visibleConversations) { conversation in
                let entry = HistoryEntryID(conversationID: conversation.id, section: .folder(folder.id))
                ChatHistoryRow(conversation: conversation, actions: actions, isSelected: selectedID == conversation.id)
                    .padding(.leading, HistoryLayout.childInset)
                    .tag(entry)
            }
            if !searching && folder.conversations.count > initialChatCount {
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
            }
        } label: {
            HStack(spacing: HistoryLayout.itemSpacing) {
                Button(action: { expanded.toggle() }) {
                    folderLabel
                }
                .buttonStyle(.plain)
                .help(folder.folder.name)
                Button(action: startChat) {
                    HistoryActionIcon("edit")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat in \(folder.folder.name)")
                .help("New chat in this folder")
            }
            .frame(minHeight: HistoryLayout.rowHeight)
            .contextMenu {
                Button(action: startChat) {
                    Label { Text("New chat in folder") } icon: { AppIcon("edit") }
                }
                Divider()
                Button(action: { renameDraft = folder.folder.name; renaming = true }) {
                    Label { Text("Rename folder") } icon: { AppIcon(systemName: "square.and.pencil") }
                }
                Divider()
                Button("Delete folder", systemImage: "trash", role: .destructive) {
                    confirmingRemoval = true
                }
            }
        }
        .listRowInsets(HistoryLayout.projectRowInsets)
        .alert("Delete \(folder.folder.name)?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: { delete(folder) })
        } message: {
            Text("Chats in this folder become simple chats again. The folder itself is removed.")
        }
        .alert("Rename folder", isPresented: $renaming) {
            TextField("Folder name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renaming = false }
            Button("Rename", action: {
                renaming = false
                rename(folder, renameDraft)
            }).disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Give the folder a new name.")
        }
        .onChange(of: selectedID) { _, id in
            if id != nil { expanded = true }
        }
    }
    private var folderLabel: some View {
        HStack(spacing: HistoryLayout.itemSpacing) {
            Image(systemName: "folder")
                .imageScale(.small)
                .frame(width: DLSSize.iconSmall)
            Text(folder.folder.name).lineLimit(1)
        }
        .dlsFont(.historyBody).fontWeight(.regular)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func startChat() {
        expanded = true
        newChat(folder.folder)
    }
}
