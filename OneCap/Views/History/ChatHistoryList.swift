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
    let actions: ChatHistoryActions
    
    var body: some View {
        List(selection: Binding(get: { selectedID }, set: { id in if let id { select(id) } })) {
            let pinned = conversations.filter(\.isPinned)
            if !pinned.isEmpty {
                Section { rows(pinned) } header: {
                    Text("Pinned").font(DLSTypography.historySection)
                }
            }
            Section {
                ForEach(conversations.historyProjects(in: projectFolders)) { project in
                    HistoryProjectGroup(
                        project: project, selected: selectedFolder?.standardizedFileURL.path == project.id,
                        open: { openProject(project.folder) },
                        newChat: { newProjectChat(project.folder) }, actions: actions)
                }
            } header: {
                HStack {
                    Text("Projects").font(DLSTypography.historySection)
                    Spacer()
                    Button("Add project folder", systemImage: "plus", action: addProject)
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                        .help("Add a project directory")
                }
                .padding(7)
            }
            let recents = conversations.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
            if !recents.isEmpty {
                Section { rows(recents) } header: {
                    Text("Recents").font(DLSTypography.historySection)
                }
            }
        }
        .disabled(busy)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
    
    private func rows(_ conversations: [ChatConversation]) -> some View {
        ForEach(conversations) { conversation in
            ChatHistoryRow(conversation: conversation, actions: actions).tag(conversation.id)
        }
    }
}
