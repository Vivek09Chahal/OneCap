import DLS
import SwiftUI

struct HistoryProjectGroup: View {
    let project: ChatHistoryProject
    let selectedEntry: HistoryEntryID?
    let selected: Bool
    let open: () -> Void
    let newChat: () -> Void
    let actions: ChatHistoryActions
    @State private var expanded = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if project.conversations.isEmpty {
                Text("No chats yet").font(DLSTypography.historyCaption).foregroundStyle(.secondary)
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
            HStack(spacing: DLSSpacing.sm) {
                Button(action: open) {
                    HStack(spacing: DLSSpacing.sm) {
                        Image(systemName: selected ? "folder.fill" : "folder")
                            .frame(width: DLSSize.iconSmall)
                            .foregroundStyle(.secondary)
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
                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                .help("New chat in this project")
            }
            .frame(minHeight: HistoryLayout.rowHeight)
            .contextMenu {
                Button("New chat in project", systemImage: "square.and.pencil", action: startChat)
            }
        }
        .listRowInsets(HistoryLayout.rowInsets)
        .onChange(of: selected) { _, selected in
            if selected { expanded = true }
        }
    }
    private func startChat() {
        expanded = true
        newChat()
    }
    
}
