import DLS
import SwiftUI

struct SkillEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var record: SharedSkill?
    @State private var name = "project-context"
    @State private var text = "# Project context\n\nDescribe the project, coding conventions, and instructions all agents should follow.\n"
    @State private var notice: String?
    @State private var loading = false
    @State private var loadFailed = false
    @State private var saving = false
    @State private var sourceURL = ""
    @State private var fetching = false
    @State private var fetchTask: Task<Void, Never>?
    let project: URL?

    init(skill: SharedSkill?, project: URL?) {
        _record = State(initialValue: skill)
        self.project = project
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            Text(record?.name ?? "New skill").font(DLSTypography.heading)
            if record == nil {
                VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                    Text("Import from URL (optional)").font(DLSTypography.callout)
                    HStack {
                        TextField("https://github.com/owner/repo/blob/main/SKILL.md", text: $sourceURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Markdown file URL")
                            .onSubmit(fetchMarkdown)
                            .disabled(fetching)
                        if fetching { ProgressView().controlSize(.small) }
                        Button(fetching ? "Fetching…" : "Fetch", action: fetchMarkdown)
                            .disabled(fetching || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Paste a public GitHub file link or raw Markdown URL. Press Return or Fetch, then edit the content below.")
                        .font(DLSTypography.caption).foregroundStyle(.secondary)
                }
                TextField("Skill name, e.g. dsa-context", text: $name).textFieldStyle(.roundedBorder)
                    .disabled(fetching)
                Text(project.map { "Project: \($0.path)" } ?? "Global: available in every chat")
                    .font(DLSTypography.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $text).font(DLSTypography.body.monospaced())
                .border(.secondary.opacity(0.25))
                .accessibilityLabel("Skill Markdown content")
                .disabled(fetching)
            if let record {
                Text(record.file.path).font(DLSTypography.monoCaption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let notice { Text(notice).font(DLSTypography.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : (record == nil ? "Add skill" : "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || fetching || saving || loadFailed || store.sending || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DLSSpacing.xxl)
        .frame(width: 680, height: record == nil ? 620 : 500)
        .disabled(loading || saving)
        .onDisappear { fetchTask?.cancel() }
        .task {
            guard let record else { return }
            loading = true
            defer { loading = false }
            do { text = try await store.skillFiles.read(record) } catch {
                loadFailed = true
                notice = error.localizedDescription
            }
        }
    }

    private func fetchMarkdown() {
        guard !fetching, !saving, !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fetching = true
        notice = nil
        let input = sourceURL
        fetchTask = Task {
            defer { fetching = false }
            do {
                let fetched = try await store.skillFiles.fetchMarkdown(input)
                try Task.checkCancellation()
                name = fetched.name
                text = fetched.text
            } catch {
                if !Task.isCancelled { notice = error.localizedDescription }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.loadSkills()
                if let record {
                    try await store.skillFiles.save(record, text: text)
                } else {
                    let contents = SkillFiles.contents(name: name, text: text)
                    record = try await store.skillFiles.create(name: name, text: contents, project: project)
                    text = contents
                }
                if let record { try await store.saveSkill(record) }
                dismiss()
            } catch { notice = error.localizedDescription }
        }
    }
}
