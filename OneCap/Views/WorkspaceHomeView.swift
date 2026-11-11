import DLS
import Lottie
import SwiftUI

/// The project desk is independent of the active chat, so replies continue while browsing.
struct WorkspaceHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @Environment(\.selectChat) private var selectChat
    @Environment(\.dlsReduceMotion) private var reduceMotion
    let searchRequest: Int
    let newChat: (URL?) -> Void
    @State private var query = ""
    @State private var selectedFolder: URL?
    @FocusState private var searchFocused: Bool

    private var busy: Bool { store.applyingFileUndo || store.savingReviewedFile }
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var projects: [ChatHistoryProject] {
        store.conversations.filter { !$0.isArchived }.historyProjects(in: store.projectFolders)
    }
    private var visibleProjects: [ChatHistoryProject] {
        projects.filter { search.isEmpty || $0.folder.path.localizedStandardContains(search) }
    }
    private var chats: [ChatConversation] {
        store.conversations.filter {
            !$0.isArchived && $0.matches(search)
            && (selectedFolder == nil || $0.workspace?.standardizedFileURL == selectedFolder)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.colors.textSecondary)
                    TextField("Search projects and chats", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("Search projects and chats")
                }
                .padding(10)
                .frame(maxWidth: 480)
                .background(theme.colors.surface, in: Capsule())
                .overlay(Capsule().stroke(theme.colors.border, lineWidth: 1))
                Spacer(minLength: 0)
                Button(action: addFolder) {
                    Label("Add folder", systemImage: "plus").padding(.horizontal, 12).padding(.vertical, 8)
                        .background(theme.colors.surface, in: Capsule())
                        .overlay(Capsule().stroke(theme.colors.border, lineWidth: 1))
                }
                Button { newChat(selectedFolder) } label: {
                    Label("New chat", systemImage: "square.and.pencil").padding(.horizontal, 12).padding(.vertical, 8)
                        .background(theme.colors.surface, in: Capsule())
                        .overlay(Capsule().stroke(theme.colors.border, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)

            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 28) {
                    projectDesk
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    chatPanel
                        .frame(width: min(390, geometry.size.width * 0.38))
                }
            }
        }
        .padding(28)
        .foregroundStyle(theme.colors.textPrimary)
        .onChange(of: searchRequest) { _, _ in searchFocused = true }
        .onChange(of: store.projectFolders) { _, folders in
            if let selectedFolder, !folders.contains(where: { $0.standardizedFileURL == selectedFolder }) {
                self.selectedFolder = nil
            }
        }
    }

    private var projectDesk: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting).font(.system(size: 38, weight: .regular, design: .serif))
                    Text("A little space for big ideas.")
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Text("Projects").font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.colors.textSecondary)
                if projects.isEmpty {
                    VStack(spacing: 12) {
                        LottieView { try await DotLottieFile.named("emptyChat") }
                            .playing(loopMode: .repeat(1))
                            .animationSpeed(reduceMotion ? 0 : 1)
                            .frame(width: 200, height: 200)
                            .accessibilityHidden(true)
                        Text("Your projects start here").font(.title3)
                        Text("Add a folder to work with its files and chats.")
                            .foregroundStyle(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Add folder", action: addFolder).buttonStyle(.borderedProminent)
                            .disabled(busy)
                    }
                    .frame(maxWidth: .infinity)
                } else if visibleProjects.isEmpty {
                    Text("No matching projects").foregroundStyle(theme.colors.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 24) {
                        ForEach(visibleProjects) { project in
                            projectTile(project)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
    }

    private func projectTile(_ project: ChatHistoryProject) -> some View {
        let selected = selectedFolder == project.folder.standardizedFileURL
        return Button {
            selectedFolder = project.folder.standardizedFileURL
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(theme.colors.textSecondary.opacity(0.35))
                    .overlay {
                        Image(systemName: "folder")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundStyle(theme.colors.textSecondary.opacity(0.3))
                    }
                Text(project.folder.lastPathComponent).font(.body.weight(.medium)).lineLimit(2)
                Text("\(project.conversations.count) \(project.conversations.count == 1 ? "chat" : "chats")")
                    .font(.caption).foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(8)
            .background(selected ? theme.colors.accentSubtle : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(project.folder.path)
        .accessibilityLabel("\(project.folder.lastPathComponent), \(project.conversations.count) chats")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(selectedFolder?.lastPathComponent ?? "Recent chats")
                    .font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if selectedFolder != nil {
                    Button("All chats") { selectedFolder = nil }.buttonStyle(.plain)
                        .foregroundStyle(theme.colors.accent)
                }
            }
            if chats.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(search.isEmpty ? "No chats yet" : "No matching chats")
                        .foregroundStyle(theme.colors.textSecondary)
                    if search.isEmpty {
                        Button("New chat") { newChat(selectedFolder) }.disabled(busy)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(chats) { chat in
                            Button { selectChat(chat.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(chat.title).font(.body.weight(.medium)).lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(chat.updatedAt, style: .relative).font(.caption)
                                            .foregroundStyle(theme.colors.textSecondary)
                                    }
                                    Text(chat.messages.last(where: { !$0.text.isEmpty })?.text ?? chat.draft)
                                        .font(.subheadline).lineLimit(2)
                                        .foregroundStyle(theme.colors.textSecondary)
                                    Text(chat.workspace?.lastPathComponent ?? "General")
                                        .font(.caption).foregroundStyle(theme.colors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.colors.border, lineWidth: 1))
    }

    private func addFolder() {
        Task {
            guard let folder = await WorkspaceFolderPicker.choose() else { return }
            store.rememberProject(folder)
            selectedFolder = folder.standardizedFileURL
        }
    }
}
