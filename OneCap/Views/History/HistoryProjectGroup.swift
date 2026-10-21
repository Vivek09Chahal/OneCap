import DLS
import SwiftUI

struct HistoryProjectGroup: View {
    let project: ChatHistoryProject
    let selectedEntry: HistoryEntryID?
    let selected: Bool
    let open: () -> Void
    let newChat: () -> Void
    let remove: () -> Void
    let actions: ChatHistoryActions
    @State private var expanded = true
    @State private var confirmingRemoval = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if project.conversations.isEmpty {
                Text("No chats yet").font(DLSTypography.historyCaption)
                    .frame(minHeight: HistoryLayout.rowHeight, alignment: .leading)
                    .padding(.leading, HistoryLayout.childInset)
                    .listRowInsets(HistoryLayout.rowInsets)
            }
            ForEach(project.conversations) { conversation in
                let entry = HistoryEntryID(conversationID: conversation.id, section: .project(project.id))
                ChatHistoryRow(conversation: conversation, actions: actions, isSelected: selectedEntry == entry)
                    .padding(.leading, HistoryLayout.childInset)
                    .tag(entry)
            }
        } label: {
            HStack(spacing: HistoryLayout.itemSpacing) {
                Button(action: open) {
                    HStack(spacing: HistoryLayout.itemSpacing) {
                        Image(systemName: selected ? "folder.fill" : "folder")
                            .frame(width: DLSSize.iconSmall)
                        Text(project.folder.lastPathComponent).lineLimit(1)
                    }
                        .font(DLSTypography.historyBody).fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(project.folder.path)
                Button(
                    "New chat in \(project.folder.lastPathComponent)", systemImage: "square.and.pencil", action: startChat
                )
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .help("New chat in this project")
            }
            .frame(minHeight: HistoryLayout.rowHeight)
            .contextMenu {
                Button("New chat in project", systemImage: "square.and.pencil", action: startChat)
                Divider()
                Button("Remove project", systemImage: "trash", role: .destructive) {
                    confirmingRemoval = true
                }
            }
        }
        .listRowInsets(HistoryLayout.rowInsets)
        .alert("Remove \(project.folder.lastPathComponent)?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("This permanently removes the project and all its saved chats from OneCap on this Mac. The folder and its files stay on disk.")
        }
        .onChange(of: selected) { _, selected in
            if selected { expanded = true }
        }
    }
    private func startChat() {
        expanded = true
        newChat()
    }
}
