import DLS
import Kingfisher
import SwiftUI

struct PluginsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @State private var query = ""
    @State private var category = "All"
    @State private var installedOnly = false
    @State private var selection: PluginEditorSelection?
    @State private var notice: String?

    private var categories: [String] { ["All"] + Set(PluginCatalog.plugins.map(\.category)).sorted() }
    private var visible: [PluginDefinition] {
        PluginCatalog.plugins.filter { plugin in
            (category == "All" || plugin.category == category) &&
            (query.isEmpty || "\(plugin.name) \(plugin.summary) \(plugin.category)".localizedCaseInsensitiveContains(query)) &&
            (!installedOnly || store.plugins.contains(where: { $0.pluginID == plugin.id }))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DLSSpacing.lg) {
                HStack(alignment: .center, spacing: DLSSpacing.lg) {
                    ManagementPageHeader(title: "Plugins", subtitle: "Your favorite apps, connected to your workflow.")
                    Spacer(minLength: DLSSpacing.md)
                    Button("Custom MCP connection", systemImage: "plus") { selection = .init() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DLSSpacing.lg) {
                        searchField
                        catalogFilters
                    }
                    VStack(alignment: .leading, spacing: DLSSpacing.md) {
                        searchField
                        catalogFilters
                    }
                }
                if let notice { Text(notice).foregroundStyle(theme.colors.warning).textSelection(.enabled) }
                InstalledPluginPackagesView()
                Divider()
                if !store.plugins.isEmpty {
                    Text("Your connections").dlsFont(.heading)
                    ForEach(store.plugins) { connection in
                        connectionRow(connection)
                    }
                    Divider()
                }
                HStack {
                    Text("Explore plugins").dlsFont(.heading)
                    Text("\(visible.count)")
                        .dlsFont(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, DLSSpacing.sm)
                        .padding(.vertical, DLSSpacing.xs)
                        .background(theme.colors.surface, in: Capsule())
                }
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .top)], alignment: .leading, spacing: DLSSpacing.md) {
                    ForEach(visible) { plugin in
                        VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                            HStack {
                                PluginIcon(plugin: plugin)
                                Text(plugin.name).dlsFont(.heading)
                                Spacer()
                            }
                            Text(plugin.category).dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                            Text(plugin.summary).dlsFont(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: DLSSpacing.sm)
                            HStack {
                                Text(plugin.accountProvider.map { "\($0) account" } ?? "App integration")
                                    .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                                Spacer()
                                Button("Connect") { selection = .init(plugin: plugin) }
                            }
                        }
                        .padding(DLSSpacing.lg)
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
                    }
                }
            }
            .padding(DLSSpacing.xxxl)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Plugins")
        .task {
            await store.refreshPluginPackages()
            do { try await store.loadPlugins() }
            catch { notice = error.localizedDescription }
        }
        .sheet(item: $selection) { item in
            if item.connection?.managedConnectionID != nil || (item.plugin != nil && item.connection == nil) {
                ManagedPluginConnectionEditor(selection: item)
            } else {
                PluginConnectionEditor(selection: item)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DLSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.colors.textSecondary)
            TextField("Search plugins", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search plugins")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(DLSSpacing.md)
        .frame(minWidth: 200)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.medium))
    }

    private var catalogFilters: some View {
        HStack(spacing: DLSSpacing.lg) {
            Picker("Category", selection: $category) {
                ForEach(categories, id: \.self) { Text($0 == "All" ? "All categories" : $0).tag($0) }
            }
            .labelsHidden()
            .accessibilityLabel("Category")
            .frame(width: 180)
            Toggle("Connected only", isOn: $installedOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private func connectionRow(_ connection: PluginConnection) -> some View {
        HStack(spacing: DLSSpacing.md) {
            PluginIcon(
                plugin: PluginCatalog.plugins.first { $0.id == connection.pluginID },
                name: connection.name
            )
            Toggle("Enable \(connection.name)", isOn: Binding(get: {
                store.plugins.first(where: { $0.id == connection.id })?.enabled ?? false
            }, set: { enabled in
                var updated = connection; updated.enabled = enabled
                Task {
                    do { try await store.savePlugin(updated, token: nil); notice = nil }
                    catch { notice = error.localizedDescription }
                }
            })).labelsHidden().toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                Text(connection.name).dlsFont(.body)
                Text("\(connection.toolCount) tools at last check · \(connection.project?.lastPathComponent ?? "All chats")")
                    .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
                Text(connection.managedConnectionID == nil ? connection.endpoint : "Account linked")
                    .dlsFont(.monoCaption).foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Manage") {
                selection = .init(plugin: PluginCatalog.plugins.first(where: { $0.id == connection.pluginID }), connection: connection)
            }
        }.padding(DLSSpacing.md)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.small))
    }
}

private struct PluginIcon: View {
    @Environment(\.dlsTheme) private var theme
    let plugin: PluginDefinition?
    var name = "Plugin"

    private var initials: String {
        let words = (plugin?.name ?? name).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if let url = plugin?.iconURL {
                KFImage(url)
                    .cacheOriginalImage()
                    .memoryCacheExpiration(.days(7))
                    .diskCacheExpiration(.days(30))
                    .cancelOnDisappear(true)
                    .placeholder { initialsPlaceholder }
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .padding(7)
                    .background(.white)
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }

    private var initialsPlaceholder: some View {
        Text(initials)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.colors.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.accentSubtle)
    }
}

struct PluginEditorSelection: Identifiable {
    let id = UUID()
    var plugin: PluginDefinition?
    var connection: PluginConnection?
}

private struct PluginConnectionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: PluginEditorSelection
    @State private var name: String
    @State private var endpoint: String
    @State private var token = ""
    @State private var replaceToken = false
    @State private var project: URL?
    @State private var busy = false
    @State private var error: String?
    @State private var removal = false

    init(selection: PluginEditorSelection) {
        self.selection = selection
        _name = State(initialValue: selection.connection?.name ?? selection.plugin?.name ?? "")
        _endpoint = State(initialValue: selection.connection?.endpoint ?? selection.plugin?.endpoint ?? "")
        _project = State(initialValue: selection.connection?.project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            HStack(spacing: DLSSpacing.md) {
                PluginIcon(plugin: selection.plugin, name: selection.connection?.name ?? "Plugin")
                Text(selection.connection == nil ? "Connect \(selection.plugin?.name ?? "plugin")" : "Manage connection").dlsFont(.heading)
            }
            if let plugin = selection.plugin {
                Text(plugin.setup).dlsFont(.callout).textSelection(.enabled)
                Link("Service setup documentation", destination: plugin.website)
            }
            Form {
                TextField("Connection name", text: $name)
                TextField("MCP endpoint", text: $endpoint, prompt: Text("https://your-server.example/mcp"))
                    .autocorrectionDisabled()
                if selection.connection?.hasCredential == true {
                    Toggle("Replace saved access token", isOn: $replaceToken)
                    if replaceToken { SecureField("New token (empty removes it)", text: $token) }
                } else { SecureField("Access token (optional)", text: $token) }
                Picker("Available in", selection: $project) {
                    Text("All chats").tag(URL?.none)
                    ForEach(projectChoices, id: \.self) { Text($0.path).tag(Optional($0)) }
                }
            }
            Text("Advanced setup for a custom Streamable HTTP MCP server. Access tokens stay in macOS Keychain. To link an app account, choose the app from the catalog instead.")
                .dlsFont(.caption).foregroundStyle(.secondary)
            Text("Connections can apply to all chats or a selected project. Provider chats ask before each action; agent harnesses manage their own permissions. Changes apply on the next message.")
                .dlsFont(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if selection.connection != nil { Button("Disconnect", role: .destructive) { removal = true } }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Test & save", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endpoint.isEmpty)
            }
        }
        .padding(DLSSpacing.xxl).frame(width: 580)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .confirmationDialog("Disconnect this plugin?", isPresented: $removal) {
            Button("Disconnect", role: .destructive) {
                guard let connection = selection.connection else { return }
                busy = true
                Task {
                    defer { busy = false }
                    do { try await store.removePlugin(connection); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("Removes the saved connection and local token. Revoke the token in the service’s account settings if it is no longer needed.") }
    }

    private var projectChoices: [URL] {
        Array(Set(store.projectFolders + [project, store.workspace].compactMap { $0 })).sorted { $0.path < $1.path }
    }

    private func save() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let url = try PluginConnection.validatedEndpoint(endpoint)
                var connection = selection.connection ?? PluginConnection(
                    pluginID: selection.plugin?.id ?? "custom", name: name, endpoint: url.absoluteString,
                    toolCount: 0, verifiedAt: Date(), hasCredential: false)
                let replacement: String? = connection.hasCredential && !replaceToken ? nil : token.trimmingCharacters(in: .whitespacesAndNewlines)
                if connection.hasCredential && connection.endpoint != url.absoluteString && !replaceToken {
                    throw AppFailure("Replace or remove the saved token when changing the endpoint.")
                }
                let credential = try replacement ?? (connection.hasCredential ? Keychain.read(connection.id) : nil)
                let client = try PluginMCPClient(endpoint: url.absoluteString, token: credential)
                let tools: [PluginTool]
                do { tools = try await client.tools() }
                catch { await client.close(); throw error }
                await client.close()
                guard !tools.isEmpty else { throw AppFailure("This connector exposes no tools. Check its configuration before saving.") }
                connection.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                connection.endpoint = url.absoluteString
                connection.project = project
                connection.toolCount = tools.count
                connection.verifiedAt = Date()
                try await store.savePlugin(connection, token: replacement)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PluginToolPermissionView: View {
    let request: PluginToolRequest
    let resolve: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Text("Allow \(request.plugin) action?").dlsFont(.heading)
            Text(request.tool).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            ScrollView { Text(request.arguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 220)
            Text("This action may read or change data in your connected account.").foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Decline") { resolve(false) }.keyboardShortcut(.cancelAction)
                Button("Allow once") { resolve(true) }.buttonStyle(.borderedProminent)
            }
        }.padding(DLSSpacing.xxl).frame(width: 520)
    }
}

private struct ManagedPluginConnectionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: PluginEditorSelection
    @State private var client: ManagedPluginClient?
    @State private var ready = false
    @State private var loading = true
    @State private var busy = false
    @State private var message: String?
    @State private var project: URL?
    @State private var operation: Task<Void, Never>?
    @State private var removal = false

    private var pluginID: String { selection.plugin?.id ?? selection.connection?.pluginID ?? "" }
    private var name: String { selection.plugin?.name ?? selection.connection?.name ?? "App" }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            HStack(spacing: DLSSpacing.md) {
                PluginIcon(plugin: selection.plugin, name: name)
                Text(selection.connection == nil ? "Connect \(name)" : "Manage \(name)").dlsFont(.heading)
            }
            Text("Sign in in your browser and choose the account you want Edth to use. You'll see the requested permissions before you approve.")
                .dlsFont(.callout)
            if selection.connection == nil {
                Picker("Available in", selection: $project) {
                    Text("All chats").tag(URL?.none)
                    ForEach(Array(Set(store.projectFolders + [store.workspace].compactMap { $0 })).sorted(by: { $0.path < $1.path }), id: \.self) {
                        Text($0.lastPathComponent).tag(Optional($0))
                    }
                }.disabled(busy)
            } else {
                Text("Available in \(selection.connection?.project?.lastPathComponent ?? "all chats"). Disconnect to change the linked account.")
                    .dlsFont(.callout)
            }
            Text("Account authentication is managed by Composio. Provider chats ask before each action; agent harnesses use their own permission controls.")
                .dlsFont(.caption).foregroundStyle(.secondary)
            if let message { Text(message).dlsFont(.callout).textSelection(.enabled) }
            HStack {
                if selection.connection != nil {
                    Button("Disconnect", role: .destructive) { removal = true }.disabled(busy)
                }
                Spacer()
                if loading || busy { ProgressView().controlSize(.small) }
                Button(busy ? "Cancel sign-in" : "Close") {
                    operation?.cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                if selection.connection == nil {
                    Button("Connect \(selection.plugin?.accountProvider.map { "\($0) account" } ?? "account")", action: connect)
                        .buttonStyle(.borderedProminent)
                        .disabled(!ready || busy || loading)
                }
            }
        }
        .padding(DLSSpacing.xxl)
        .frame(width: 560)
        .task { await configure() }
        .onDisappear { operation?.cancel() }
        .interactiveDismissDisabled(busy)
        .confirmationDialog("Disconnect \(name)?", isPresented: $removal) {
            Button("Disconnect", role: .destructive) {
                guard let connection = selection.connection else { return }
                busy = true
                operation = Task {
                    defer { busy = false }
                    do { try await store.removePlugin(connection); dismiss() }
                    catch { message = error.localizedDescription }
                }
            }
        } message: {
            Text("Removes this account connection from Edth and Composio. You can also revoke access in the service's account settings.")
        }
    }

    private func configure() async {
        defer { loading = false }
        do {
            if let connection = selection.connection, let service = connection.managedServiceURL {
                client = try ManagedPluginClient(baseURL: service, token: Keychain.read(connection.id))
                guard let identifier = connection.managedConnectionID, let id = UUID(uuidString: identifier) else {
                    throw AppFailure("Invalid saved connection. Disconnect it and connect again.")
                }
                // A single check also identifies expired accounts without showing an MCP form.
                try await client?.waitUntilConnected(id, attempts: 1, interval: .zero)
                message = "Account connected."
            } else {
                let configured = try ManagedPluginClient.configured()
                client = configured
                ready = try await configured.supportedPlugins().contains(pluginID)
                if !ready { message = "Account linking for \(name) is not available on the Edth connection service yet." }
            }
        } catch { message = error.localizedDescription }
    }

    private func connect() {
        guard let client else { return }
        busy = true
        message = "Opening sign-in…"
        operation = Task {
            var pending: UUID?
            var saved = false
            defer {
                busy = false
                if let pending, !saved {
                    // Use a fresh task: cancelling browser sign-in must also discard its pending connection.
                    Task { try? await client.disconnect(pending) }
                }
            }
            do {
                let link = try await client.connect(pluginID: pluginID)
                pending = link.id
                try Task.checkCancellation()
                guard NSWorkspace.shared.open(link.redirectURL) else { throw AppFailure("Could not open your browser. Please retry.") }
                message = "Waiting for sign-in. Choose an account and approve access in your browser."
                try await client.waitUntilConnected(link.id)
                let endpoint = client.endpoint(for: link.id)
                let mcp = try PluginMCPClient(endpoint: endpoint, token: client.token)
                let tools: [PluginTool]
                do { tools = try await mcp.tools() }
                catch { await mcp.close(); throw error }
                await mcp.close()
                try Task.checkCancellation()
                guard !tools.isEmpty else { throw AppFailure("This app has no available tools. Ask your administrator to check the connector configuration.") }
                let connection = PluginConnection(pluginID: pluginID, name: name, endpoint: endpoint,
                    project: project, toolCount: tools.count, verifiedAt: Date(), hasCredential: true,
                    managedConnectionID: link.id.uuidString, managedServiceURL: client.baseURL.absoluteString)
                try await store.savePlugin(connection, token: client.token)
                saved = true
                dismiss()
            } catch is CancellationError {
                message = "Sign-in cancelled."
            } catch { message = error.localizedDescription }
        }
    }
}
