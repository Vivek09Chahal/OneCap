import AppKit
import DLS
import SwiftUI

struct SkillsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @State private var project: URL?
    @State private var initialized = false
    @State private var showingEditor = false
    @State private var editing: SharedSkill?
    @State private var notice: String?

    private var visible: [SharedSkill] {
        store.skills.filter { $0.project == nil || $0.project?.standardizedFileURL == project?.standardizedFileURL }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            ManagementPageHeader(title: "Skills", subtitle: "Shared project context for every agent and model.")
            HStack(spacing: DLSSpacing.md) {
                Image(systemName: "text.bubble").foregroundStyle(theme.colors.accent)
                VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                    Text("Caveman · Built-in skill").font(DLSTypography.heading)
                    Text(BundledSkill.caveman.summary)
                        .font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
                }
                Spacer(minLength: DLSSpacing.sm)
                Link("Source", destination: BundledSkill.caveman.website)
                if store.skills.contains(where: { $0.name == "caveman" && $0.project == nil }) {
                    Label("Added", systemImage: "checkmark.circle")
                        .font(DLSTypography.caption).foregroundStyle(theme.colors.success)
                } else {
                    Button("Add Caveman") { perform { try await store.installBundledSkill(.caveman) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(DLSSpacing.lg)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
            HStack(spacing: DLSSpacing.md) {
                Text("Scope").font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
                Picker("Project", selection: $project) {
                    Text("Global skills").tag(URL?.none)
                    ForEach(store.projectFolders, id: \.self) { folder in
                        Text(folder.lastPathComponent).tag(Optional(folder))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                Button("Choose folder…") {
                    Task {
                        if let folder = await WorkspaceFolderPicker.choose() {
                            store.rememberProject(folder)
                            project = folder.standardizedFileURL
                        }
                    }
                }
                Spacer()
            }
            .tint(theme.colors.textPrimary)
            Text("Global skills apply to all chats. Project skills apply to that folder and its subfolders. Enabled instructions and their paths are included with each request.")
                .font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No skills yet", systemImage: "book.closed")
                } description: {
                    Text("No skills found in the standard folders for this scope. You can also create or import one.")
                } actions: {
                    Button("New skill") { editing = nil; showingEditor = true }
                        .buttonStyle(.borderedProminent)
                    Button("Import skill", action: importSkills).buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visible) { skill in
                    SharedSkillRow(skill: skill,
                        toggle: { enabled in
                            var updated = skill
                            updated.enabled = enabled
                            perform { try await store.saveSkill(updated) }
                        },
                        edit: { editing = skill; showingEditor = true },
                        remove: { perform { try await store.removeSkill(skill) } })
                        .disabled(store.sending)
                }
                .listStyle(.inset).scrollContentBackground(.hidden)
            }
            if let notice { Text(notice).font(DLSTypography.callout).foregroundStyle(theme.colors.warning) }
            Text("Skills are found automatically in standard agent skill folders. Turn on the skills you want to share. Changes apply to the next request; start a new chat to clear earlier context.")
                .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DLSSpacing.xxxl)
        .background(theme.colors.background)
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Rescan skills", systemImage: "arrow.clockwise") { perform { try await store.discoverSkills(project: project) } }
                Button("Import skill", systemImage: "square.and.arrow.down") { importSkills() }
                Button("New skill", systemImage: "plus") { editing = nil; showingEditor = true }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .disabled(!store.skillsLoaded || store.sending)
        .task(id: project) {
            if !initialized { project = store.workspace; initialized = true }
            do { try await store.discoverSkills(project: project); notice = nil }
            catch is CancellationError { }
            catch { notice = error.localizedDescription }
        }
        .sheet(isPresented: $showingEditor) { SkillEditor(skill: editing, project: project) }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation(); notice = nil } catch { notice = error.localizedDescription }
        }
    }

    private func importSkills() {
        let scope = project
        perform {
            let urls = await WorkspaceFolderPicker.chooseFiles(prompt: "Import skills",
                message: "Choose SKILL.md files or skill folders. Source files stay in their current location.", allowsFolders: true)
            for url in urls {
                try await store.saveSkill(store.skillFiles.imported(url, project: scope))
            }
        }
    }
}

private struct SharedSkillRow: View {
    let skill: SharedSkill
    let toggle: @MainActor @Sendable (Bool) -> Void
    let edit: () -> Void
    let remove: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: DLSSpacing.md) {
            Toggle("Enable \(skill.name)", isOn: Binding(get: { skill.enabled }, set: toggle))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                HStack {
                    Text(skill.name).font(DLSTypography.body)
                    Text(skill.project?.lastPathComponent ?? "Global").font(DLSTypography.caption).foregroundStyle(.secondary)
                    if skill.discovered == true {
                        Text("Discovered").font(DLSTypography.caption).foregroundStyle(.secondary)
                    }
                }
                Text(skill.file.path).font(DLSTypography.monoCaption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(skill.file.path)
            }
            Spacer()
            Button("Edit skill", systemImage: "pencil", action: edit)
            Button("Reveal skill file", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([skill.file]) }
            if skill.discovered != true {
                Button("Remove skill", systemImage: "minus.circle") { confirmingRemoval = true }
            }
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
        .padding(.vertical, DLSSpacing.sm)
        .confirmationDialog("Remove \(skill.name) from OneCap?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive, action: remove)
        } message: { Text("The SKILL.md file will remain on disk.") }
    }
}
