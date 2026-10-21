import AppKit
import DLS
import SwiftUI
import UniformTypeIdentifiers

struct OpenInEditorMenu: View {
    let url: URL
    @AppStorage("preferredCodeEditorPath") private var preferredPath = ""
    @State private var editors: [InstalledCodeEditor] = []
    @State private var error: String?

    private var preferred: InstalledCodeEditor? {
        editors.first(where: { $0.id == preferredPath }) ?? editors.first
    }

    var body: some View {
        Group {
            if let preferred {
                Menu {
                    ForEach(editors) { editor in
                        Button("Open in \(editor.name)") { open(editor) }
                    }
                    Divider()
                    Button("Choose another editor…", action: chooseEditor)
                } label: {
                    Text("Open in \(preferred.name)")
                } primaryAction: {
                    open(preferred)
                }
                .help("Open \(url.lastPathComponent) in \(preferred.name)")
            } else {
                Button("Open in editor…", action: chooseEditor)
                    .help("Choose an installed code editor")
            }
        }
        .controlSize(.small)
        .task(id: preferredPath) {
            editors = CodeEditorLauncher.installedEditors()
            if !preferredPath.isEmpty,
               !editors.contains(where: { $0.id == preferredPath }),
               let custom = CodeEditorLauncher.editor(at: URL(fileURLWithPath: preferredPath)) {
                editors.insert(custom, at: 0)
            }
        }
        .alert("Could not open editor", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func open(_ editor: InstalledCodeEditor) {
        Task { @MainActor in
            do {
                try await CodeEditorLauncher.open(url, in: editor)
                preferredPath = editor.id
            } catch {
                self.error = "\(editor.name): \(error.localizedDescription)"
            }
        }
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Open in editor"
        panel.message = "Choose the code editor to open this file or project."
        panel.begin { response in
            guard response == .OK, let appURL = panel.url else { return }
            guard let editor = CodeEditorLauncher.editor(at: appURL) else {
                error = "Choose a macOS editor application."
                return
            }
            open(editor)
        }
    }
}
