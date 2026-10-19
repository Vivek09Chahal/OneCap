import DLS
import SwiftUI

struct HistoryProjectGroup: View {
    let project: ChatHistoryProject
    let selected: Bool
    let open: () -> Void
    let newChat: () -> Void
    let actions: ChatHistoryActions
    @State private var expanded = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if project.conversations.isEmpty {
                Text("No chats yet").font(DLSTypography.historyCaption).foregroundStyle(.secondary)
            }
            ForEach(project.conversations) { conversation in
                ChatHistoryRow(conversation: conversation, actions: actions).tag(conversation.id)
            }
        } label: {
            HStack(spacing: DLSSpacing.sm) {
                Button(action: open) {
                    Label(project.folder.lastPathComponent, systemImage: selected ? "folder.fill" : "folder")
                        .font(DLSTypography.historyBody).lineLimit(1)
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
            .contextMenu {
                Button("New chat in project", systemImage: "square.and.pencil", action: startChat)
            }
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
