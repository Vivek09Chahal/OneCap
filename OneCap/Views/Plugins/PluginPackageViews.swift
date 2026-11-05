import AppKit
import DLS
import SwiftUI

struct InstalledPluginPackagesView: View {
    @Environment(AppStore.self) private var store
    @State private var approval: InstalledPluginPackage?
    @State private var removal: InstalledPluginPackage?
    @State private var busy = false
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            HStack {
                Text("Installed extensions").dlsFont(.heading)
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { Task { await store.refreshPluginPackages() } }
                Button("Install plugin…", systemImage: "plus") {
                    Task {
                        guard let folder = await WorkspaceFolderPicker.choose() else { return }
                        busy = true
                        defer { busy = false }
                        do { try await store.installPluginPackage(from: folder); notice = nil }
                        catch { notice = error.localizedDescription }
                    }
                }
            }
            Text("Install a plugin folder to add commands and agent tools. New plugins start disabled; enable them after reviewing their code.")
                .dlsFont(.callout).foregroundStyle(.secondary)
            if store.pluginPackages.isEmpty {
                Text("No extensions installed.").foregroundStyle(.secondary)
            }
            ForEach(store.pluginPackages) { package in
                HStack(spacing: DLSSpacing.md) {
                    Toggle(package.manifest.name, isOn: Binding(get: { package.enabled }, set: { enabled in
                        if enabled { approval = package }
                        else { update(package, enabled: false) }
                    })).labelsHidden().toggleStyle(.switch)
                    VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                        Text("\(package.manifest.name) · \(package.manifest.version)").dlsFont(.heading)
                        Text(package.manifest.summary).dlsFont(.callout)
                        Text("\(package.manifest.commands.count) commands · \(package.manifest.tools.count) provider chat tools · \(package.enabled ? "Enabled" : "Disabled")")
                            .dlsFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !package.manifest.commands.isEmpty {
                        Menu("Commands") {
                            ForEach(package.manifest.commands) { command in
                                Button(command.title) { store.pendingPluginCommand = .init(package: package, command: command) }
                            }
                        }.disabled(!package.enabled || store.runningPluginCommand)
                    }
                    Button("Show files") { NSWorkspace.shared.open(package.directory) }
                    Button("Remove", role: .destructive) { removal = package }
                }.padding(DLSSpacing.md)
            }
            if store.runningPluginCommand { ProgressView("Running plugin command…").controlSize(.small) }
            if let notice { Text(notice).foregroundStyle(.red).textSelection(.enabled) }
            ForEach(store.pluginPackageIssues, id: \.self) { Text($0).foregroundStyle(.red).textSelection(.enabled) }
        }
        .disabled(busy)
        .confirmationDialog("Enable \(approval?.manifest.name ?? "plugin")?", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } }), titleVisibility: .visible) {
            if let package = approval { Button("Enable plugin") { update(package, enabled: true); approval = nil } }
        } message: {
            Text("This runs third-party code with your macOS user’s file and network access. A separate process is not a sandbox. Enable only plugins you trust. Changes to package files disable it until you review and enable it again.")
        }
        .confirmationDialog("Remove \(removal?.manifest.name ?? "plugin")?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            if let package = removal {
                Button("Remove plugin", role: .destructive) {
                    Task {
                        do { try await store.removePluginPackage(package); notice = nil }
                        catch { notice = error.localizedDescription }
                        removal = nil
                    }
                }
            }
        } message: { Text("Deletes the installed package from OneCap. Your original folder is kept. An action already running may finish.") }
    }

    private func update(_ package: InstalledPluginPackage, enabled: Bool) {
        Task {
            busy = true
            defer { busy = false }
            do { try await store.enablePluginPackage(package, enabled: enabled); notice = nil }
            catch { notice = error.localizedDescription }
        }
    }
}

struct PluginCommandRunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: PluginCommandSelection
    @State private var arguments = "{}"
    @State private var error: String?
    @State private var result: String?
    @State private var execution: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Text(selection.command.title).dlsFont(.heading)
            Text(selection.command.description)
            Text("Provided by \(selection.package.manifest.name)").foregroundStyle(.secondary)
            if let result {
                ScrollView { Text(result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 120, maxHeight: 400)
            } else if selection.command.inputSchema["properties"] != .object([:]) {
                Text("Command inputs (JSON)")
                TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 130)
                    .disabled(execution != nil)
                DisclosureGroup("Input format") {
                    Text(String(decoding: (try? JSONEncoder().encode(selection.command.inputSchema)) ?? Data(), as: UTF8.self))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if execution != nil { ProgressView().controlSize(.small) }
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { execution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if result == nil {
                    Button("Run", action: run).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(execution != nil || store.runningPluginCommand)
                }
            }
        }.padding(DLSSpacing.xxl).frame(width: 520)
            .onDisappear { execution?.cancel() }
    }

    private func run() {
        do {
            let json = try JSONDecoder().decode(PluginJSON.self, from: Data(arguments.utf8))
            guard case .object = json else { throw AppFailure("Enter a JSON object.") }
            error = nil
            execution = Task {
                defer { execution = nil }
                do {
                    result = try await store.executePluginCommand(selection.package, command: selection.command, arguments: json)
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }
}
