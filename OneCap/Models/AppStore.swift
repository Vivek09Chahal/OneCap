import Foundation
import Observation

@MainActor @Observable final class AppStore {
    var agents: [Agent] = []
    var installed: [InstalledAgent] = []
    var providers: [Provider] = []
    var loading = false
    var installing: Set<String> = []
    var uninstalling: Set<String> = []
    var error: String?
    var catalogUpdatedAt: Date?
    var catalogRefreshFailed = false
    var messages: [ChatMessage] = []
    var fileChanges: [FileChangeSet] = []
    var reviewedChanges: FileChangeSet?
    var reviewedFilePath: String?
    var applyingFileUndo = false
    var savingReviewedFile = false
    var fileChangeError: String?
    var fileTreeRevision = UUID()
    @ObservationIgnored let fileChangeTracker = FileChangeTracker()
    var conversations: [ChatConversation] = []
    var projectFolders: [URL] = []
    var skills: [SharedSkill] = []
    @ObservationIgnored var skillsLoaded = false
    @ObservationIgnored var skillSaveTask: Task<Void, Error>?
    @ObservationIgnored let skillRepository: JSONFileRepository<[SharedSkill]>
    @ObservationIgnored let skillFiles: SkillFiles
    var chatUsesAgent = false
    var draft = ""
    var draftAttachments: [ChatAttachment] = []
    var queuedMessages: [QueuedChatMessage] = []
    var importingFiles = false
    @ObservationIgnored var attachmentImportID = UUID()
    @ObservationIgnored let fileImporter = ChatFileImporter()
    var editingMessageID: UUID?
    var editedMessageText = ""
    var stoppingReply = false
    var sending = false
    var connecting = false
    var connectionError: String?
    var authenticationNeedsRetry = false
    var status = "Choose a provider or connect an agent to begin."
    var selectedProviderID: UUID?
    var selectedAgentID: String?
    var workspace: URL?
    let acp = ACPConnection()
    let terminalLogin: TerminalLoginCoordinator
    @ObservationIgnored let installer: any AgentInstalling
    @ObservationIgnored let providerClient: any ProviderResponding
    @ObservationIgnored let repository: AppRepository
    @ObservationIgnored let chatDirectories: ChatWorkspaceDirectory
    @ObservationIgnored let projectRepository: any SnapshotRepository<[URL]>
    @ObservationIgnored var projectSaveTask: Task<Void, Never>?
    @ObservationIgnored var projectsLoaded = false
    @ObservationIgnored let conversationRepository: any SnapshotRepository<[ChatConversation]>
    @ObservationIgnored var historySaveTask: Task<Void, Never>?
    @ObservationIgnored var historyLoaded = false
    @ObservationIgnored var agentNeedsHistoryContext = false
    @ObservationIgnored var loaded = false
    var conversationID = UUID()
    @ObservationIgnored var activeConnectionID = UUID()
    @ObservationIgnored var replyID: UUID?
    @ObservationIgnored var sendTask: Task<Void, Never>?
    @ObservationIgnored var titleTasks: [UUID: Task<Void, Never>] = [:]
    
    init(
        stateURL: URL? = nil, installer: any AgentInstalling = AgentInstaller(),
        conversationRepository: (any SnapshotRepository<[ChatConversation]>)? = nil,
        projectRepository: (any SnapshotRepository<[URL]>)? = nil,
        providerClient: any ProviderResponding = ProviderClient(),
        openLoginURL: @escaping @MainActor (URL) -> Bool = LoginBrowser.open
    ) {
        let url =
        stateURL
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneCap/state.json")
        repository = AppRepository(url: url)
        skillRepository = JSONFileRepository(url: url.deletingLastPathComponent().appendingPathComponent("skills.json"))
        skillFiles = SkillFiles(globalDirectory: url.deletingLastPathComponent().appendingPathComponent("Skills"),
            homeDirectory: stateURL == nil ? FileManager.default.homeDirectoryForCurrentUser : nil)
        self.conversationRepository = conversationRepository ?? ConversationRepository(
            url: url.deletingLastPathComponent().appendingPathComponent("conversations.json"))
        self.projectRepository = projectRepository ?? ProjectRepository(
            url: url.deletingLastPathComponent().appendingPathComponent("projects.json"))
        chatDirectories = ChatWorkspaceDirectory(
            root: url.deletingLastPathComponent().appendingPathComponent("ChatWorkspaces"))
        terminalLogin = TerminalLoginCoordinator(openURL: openLoginURL)
        self.installer = installer
        self.providerClient = providerClient
        acp.onTerminalLogin = { [weak terminalLogin] command in
            guard let terminalLogin else { throw CancellationError() }
            try await terminalLogin.run(command)
        }
        acp.onOpenLoginURL = openLoginURL
        acp.onStatus = { [weak self] text in
            guard let self, self.status != text else { return }
            self.status = text
        }
        acp.onTitle = { [weak self] title in
            guard let self else { return }
            self.applyGeneratedTitle(title, to: self.conversationID)
        }
        acp.onText = { [weak self] text in
            guard let self, !self.stoppingReply, let id = self.replyID,
                  let index = self.messages.firstIndex(where: { $0.id == id })
                    else { return }
            guard !text.isEmpty else { return }
            // One in-place transcript mutation per chunk, including the first state transition.
            self.messages[index].appendResponseText(text)
        }
    }
    var selectedAgent: InstalledAgent? {
        installed.first { $0.id == selectedAgentID }
    }

    var selectedProvider: Provider? {
        providers.first { $0.id == selectedProviderID }
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        async let history: Void = loadHistory()
        do {
            let state = try await repository.load()
            installed = state.installed
            providers = state.providers
            selectedProviderID = providers.first?.id
            selectedAgentID = state.selectedAgentID
            for agent in installed {
                do {
                    let restored = try agent.acpLaunch()
                    if restored.arguments != agent.arguments || restored.executable != agent.executable {
                        _ = try await repository.register(restored)
                        if let index = installed.firstIndex(where: { $0.id == agent.id }) { installed[index] = restored }
                    }
                } catch {
                    if selectedAgentID == agent.id { connectionError = error.localizedDescription }
                }
            }
            if messages.isEmpty && !sending { chatUsesAgent = selectedAgentID != nil }
        } catch {
            loaded = false
            self.error = "Could not load saved settings: \(error.localizedDescription)"
        }
        await history
        await loadProjects()
    }
}
