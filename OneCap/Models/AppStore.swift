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
    var messages: [ChatMessage] {
        get { chatSession.messages }
        set { chatSession.messages = newValue }
    }
    var fileChanges: [FileChangeSet] {
        get { chatSession.fileChanges }
        set { chatSession.fileChanges = newValue }
    }
    var reviewedChanges: FileChangeSet? {
        get { chatSession.reviewedChanges }
        set { chatSession.reviewedChanges = newValue }
    }
    var reviewedFilePath: String? {
        get { chatSession.reviewedFilePath }
        set { chatSession.reviewedFilePath = newValue }
    }
    var applyingFileUndo: Bool {
        get { chatSession.applyingFileUndo }
        set { chatSession.applyingFileUndo = newValue }
    }
    var savingReviewedFile: Bool {
        get { chatSession.savingReviewedFile }
        set { chatSession.savingReviewedFile = newValue }
    }
    var fileChangeError: String? {
        get { chatSession.fileChangeError }
        set { chatSession.fileChangeError = newValue }
    }
    var fileTreeRevision: UUID {
        get { chatSession.fileTreeRevision }
        set { chatSession.fileTreeRevision = newValue }
    }
    var fileChangeTracker: FileChangeTracker {
        get { chatSession.fileChangeTracker }
    }
    var conversations: [ChatConversation] = []
    var allowsAgentSelectionToast = true
    var projectFolders: [URL] = []
    var skills: [SharedSkill] = []
    var skillsLoaded = false
    @ObservationIgnored var skillSaveTask: Task<Void, Error>?
    @ObservationIgnored let skillRepository: JSONFileRepository<[SharedSkill]>
    @ObservationIgnored let skillFiles: SkillFiles
    var chatUsesAgent: Bool {
        get { chatSession.chatUsesAgent }
        set { chatSession.chatUsesAgent = newValue }
    }
    var draft: String {
        get { chatSession.draft }
        set { chatSession.draft = newValue }
    }
    var draftAttachments: [ChatAttachment] {
        get { chatSession.draftAttachments }
        set { chatSession.draftAttachments = newValue }
    }
    var queuedMessages: [QueuedChatMessage] {
        get { chatSession.queuedMessages }
        set { chatSession.queuedMessages = newValue }
    }
    var importingFiles: Bool {
        get { chatSession.importingFiles }
        set { chatSession.importingFiles = newValue }
    }
    var attachmentImportID: UUID {
        get { chatSession.attachmentImportID }
        set { chatSession.attachmentImportID = newValue }
    }
    @ObservationIgnored let fileImporter = ChatFileImporter()
    var editingMessageID: UUID? {
        get { chatSession.editingMessageID }
        set { chatSession.editingMessageID = newValue }
    }
    var editedMessageText: String {
        get { chatSession.editedMessageText }
        set { chatSession.editedMessageText = newValue }
    }
    var stoppingReply: Bool {
        get { chatSession.stoppingReply }
        set { chatSession.stoppingReply = newValue }
    }
    var sending: Bool {
        get { chatSession.sending }
        set { chatSession.sending = newValue }
    }
    var connecting: Bool {
        get { chatSession.connecting }
        set { chatSession.connecting = newValue }
    }
    var connectionError: String? {
        get { chatSession.connectionError }
        set { chatSession.connectionError = newValue }
    }
    var authenticationNeedsRetry: Bool {
        get { chatSession.authenticationNeedsRetry }
        set { chatSession.authenticationNeedsRetry = newValue }
    }
    var status: String {
        get { chatSession.status }
        set { chatSession.status = newValue }
    }
    var selectedProviderID: UUID? {
        get { chatSession.selectedProviderID }
        set { chatSession.selectedProviderID = newValue }
    }
    var selectedAgentID: String? {
        get { chatSession.selectedAgentID }
        set { chatSession.selectedAgentID = newValue }
    }
    var workspace: URL? {
        get { chatSession.workspace }
        set { chatSession.workspace = newValue }
    }
    var acp: ACPConnection {
        get { chatSession.acp }
    }
    var terminalLogin: TerminalLoginCoordinator {
        get { chatSession.terminalLogin }
    }
    @ObservationIgnored let installer: any AgentInstalling
    @ObservationIgnored let providerClient: any ProviderResponding
    @ObservationIgnored let repository: AppRepository
    @ObservationIgnored let storageReader: AppStorageReader
    @ObservationIgnored let chatDirectories: ChatWorkspaceDirectory
    @ObservationIgnored let projectRepository: any SnapshotRepository<[URL]>
    @ObservationIgnored var projectSaveTask: Task<Void, Never>?
    @ObservationIgnored var projectsLoaded = false
    @ObservationIgnored let conversationRepository: any SnapshotRepository<[ChatConversation]>
    @ObservationIgnored var historySaveTask: Task<Void, Never>?
    @ObservationIgnored var historyLoaded = false
    var agentNeedsHistoryContext: Bool {
        get { chatSession.agentNeedsHistoryContext }
        set { chatSession.agentNeedsHistoryContext = newValue }
    }
    @ObservationIgnored var loaded = false
    @ObservationIgnored var catalogLoaded = false
    var conversationID: UUID {
        get { chatSession.conversationID }
        set { chatSession.conversationID = newValue }
    }
    var activeConnectionID: UUID {
        get { chatSession.activeConnectionID }
        set { chatSession.activeConnectionID = newValue }
    }
    var replyID: UUID? {
        get { chatSession.replyID }
        set { chatSession.replyID = newValue }
    }
    var sendTask: Task<Void, Never>? {
        get { chatSession.sendTask }
        set { chatSession.sendTask = newValue }
    }
    @ObservationIgnored var titleTasks: [UUID: Task<Void, Never>] = [:]
    
    var chatSession: ChatSession
    @ObservationIgnored var chatSessions: [UUID: ChatSession] = [:]
    @ObservationIgnored let openLoginURL: @MainActor (URL) -> Bool

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
        storageReader = AppStorageReader(root: url.deletingLastPathComponent())
        skillRepository = JSONFileRepository(url: url.deletingLastPathComponent().appendingPathComponent("skills.json"))
        skillFiles = SkillFiles(globalDirectory: url.deletingLastPathComponent().appendingPathComponent("Skills"),
            homeDirectory: stateURL == nil ? FileManager.default.homeDirectoryForCurrentUser : nil)
        self.conversationRepository = conversationRepository ?? ConversationRepository(
            url: url.deletingLastPathComponent().appendingPathComponent("conversations.json"))
        self.projectRepository = projectRepository ?? ProjectRepository(
            url: url.deletingLastPathComponent().appendingPathComponent("projects.json"))
        chatDirectories = ChatWorkspaceDirectory(
            root: url.deletingLastPathComponent().appendingPathComponent("ChatWorkspaces"))
        self.openLoginURL = openLoginURL
        chatSession = ChatSession(openLoginURL: openLoginURL)
        self.installer = installer
        self.providerClient = providerClient
        configureSession(chatSession)
    }

    func configureSession(_ session: ChatSession) {
        session.acp.onTerminalLogin = { [weak terminalLogin = session.terminalLogin] command in
            guard let terminalLogin else { throw CancellationError() }
            try await terminalLogin.run(command)
        }
        session.acp.onOpenLoginURL = openLoginURL
        session.acp.onStatus = { [weak session] text in
            guard let session, session.status != text else { return }
            session.status = text
        }
        session.acp.onTitle = { [weak self, weak session] title in
            guard let self, let session else { return }
            self.applyGeneratedTitle(title, to: session.conversationID)
        }
        session.acp.onText = { [weak session] text in
            guard let session, !session.stoppingReply, let id = session.replyID,
                  let index = session.messages.firstIndex(where: { $0.id == id })
                    else { return }
            guard !text.isEmpty else { return }
            // One in-place transcript mutation per chunk, including the first state transition.
            session.messages[index].appendResponseText(text)
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
