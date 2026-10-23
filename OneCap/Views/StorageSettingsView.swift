import AppKit
import DLS
import SwiftUI

struct StorageSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme
    @State private var usage: AppStorageUsage?
    @State private var refreshing = false
    @State private var refreshID = UUID()
    @State private var location: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xxxl) {
            VStack(alignment: .leading, spacing: DLSSpacing.lg) {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    Text("This device").font(DLSTypography.heading)
                    Text("The app and local data stored on this Mac.")
                        .foregroundStyle(theme.colors.textSecondary)
                }
                HStack {
                    Text(usage.map { "\(formatted($0.total)) used by OneCap" } ?? "Calculating storage…")
                        .font(DLSTypography.heading)
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small) }
                    Button("Refresh") { refreshID = UUID() }
                        .disabled(refreshing)
                }
                if let usage {
                    storageBar(usage)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: DLSSpacing.xl) { legend(usage) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)],
                                  alignment: .leading, spacing: DLSSpacing.lg) { legend(usage) }
                    }
                    if usage.unreadableItems > 0 {
                        Text("Some files could not be read. The total shown may be incomplete.")
                            .font(DLSTypography.callout).foregroundStyle(theme.colors.warning)
                    }
                }
                if let location {
                    Text(location.path).font(DLSTypography.caption)
                        .foregroundStyle(theme.colors.textSecondary).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                }
            }
            HStack(spacing: DLSSpacing.lg) {
                VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                    Text("Local app data")
                    Text("Chats, agent installations, skills, and chat workspaces.")
                        .font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
                }
                Spacer(minLength: 0)
                Button("Show in Finder") {
                    if let location { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path) }
                }
                .disabled(location == nil)
            }
            .cardSurface()
            if let usage {
                VStack(alignment: .leading, spacing: DLSSpacing.lg) {
                    Text("Storage locations").font(DLSTypography.heading)
                    ForEach(AppStorageUsage.Category.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: DLSSpacing.md) {
                            HStack(spacing: DLSSpacing.sm) {
                                Circle().fill(color(category)).frame(width: 8, height: 8)
                                Text(category.rawValue).font(DLSTypography.heading)
                                Spacer()
                                Text(formatted(usage.bytes[category, default: 0]))
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            let paths = usage.locations[category, default: []].sorted { $0.path < $1.path }
                            ForEach(paths, id: \.self) { path in
                                HStack(alignment: .top, spacing: DLSSpacing.lg) {
                                    Text(path.path)
                                        .font(DLSTypography.monoCaption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([path])
                                    }
                                    .disabled(!FileManager.default.fileExists(atPath: path.path))
                                    .accessibilityLabel("Show \(path.lastPathComponent) in Finder")
                                }
                            }
                            if paths.isEmpty {
                                Text("No location available.")
                                    .font(DLSTypography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                        .cardSurface()
                    }
                }
            }
            Text("Includes the application, its support files, preferences, and caches. Linked project folders and data managed by external agents are excluded. Storage is measured from allocated file sizes; shared files may use less physical disk space.")
                .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: refreshID) {
            refreshing = true
            defer { refreshing = false }
            location = store.storageReader.root
            do { usage = try await store.storageReader.measure() }
            catch is CancellationError { }
            catch { store.error = error.localizedDescription }
        }
    }

    private func storageBar(_ usage: AppStorageUsage) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(AppStorageUsage.Category.allCases, id: \.self) { category in
                    Rectangle().fill(color(category))
                        .frame(width: geometry.size.width * CGFloat(usage.bytes[category, default: 0]) /
                               CGFloat(max(usage.total, 1)))
                }
            }
        }
        .frame(height: 24)
        .background(theme.colors.selection)
        .clipShape(RoundedRectangle(cornerRadius: DLSRadius.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage used by OneCap: \(formatted(usage.total))")
    }

    private func legend(_ usage: AppStorageUsage) -> some View {
        ForEach(AppStorageUsage.Category.allCases, id: \.self) { category in
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                HStack(spacing: DLSSpacing.sm) {
                    Circle().fill(color(category)).frame(width: 8, height: 8)
                    Text(category.rawValue).fixedSize()
                }
                Text(formatted(usage.bytes[category, default: 0]))
            }
            .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func color(_ category: AppStorageUsage.Category) -> Color {
        switch category {
        case .application: .blue
        case .chats: .yellow
        case .workspaces: theme.colors.success
        case .agents: .purple
        case .skills: theme.colors.accent
        case .other: theme.colors.textTertiary
        }
    }
}
