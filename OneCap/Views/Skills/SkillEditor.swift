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
    let project: URL?

    init(skill: SharedSkill?, project: URL?) {
        _record = State(initialValue: skill)
        self.project = project
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            Text(record?.name ?? "New skill").font(DLSTypography.heading)
            if record == nil {
                TextField("Skill name, e.g. dsa-context", text: $name).textFieldStyle(.roundedBorder)
                Text(project.map { "Project: \($0.path)" } ?? "Global: available in every chat")
                    .font(DLSTypography.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $text).font(DLSTypography.body.monospaced())
                .border(.secondary.opacity(0.25))
            if let record {
                Text(record.file.path).font(DLSTypography.monoCaption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let notice { Text(notice).font(DLSTypography.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || saving || loadFailed || store.sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DLSSpacing.xxl)
        .frame(width: 620, height: 500)
        .disabled(loading || saving)
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

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.loadSkills()
                if let record {
                    try await store.skillFiles.save(record, text: text)
                } else {
                    let contents = "---\nname: \(name)\ndescription: Shared context for coding agents in OneCap\n---\n\n" + text
                    record = try await store.skillFiles.create(name: name, text: contents, project: project)
                    text = contents
                }
                if let record { try await store.saveSkill(record) }
                dismiss()
            } catch { notice = error.localizedDescription }
        }
    }
}
