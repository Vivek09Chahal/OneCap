import Foundation
import Observation

@MainActor @Observable
final class FolderTreeModel {
    struct Row: Identifiable {
        let entry: FolderEntry
        let depth: Int
        var id: URL { entry.id }
    }

    private(set) var root: URL?
    private(set) var children: [URL: [FolderEntry]] = [:]
    private(set) var expanded: Set<URL> = []
    private(set) var loading: Set<URL> = []
    private(set) var errors: [URL: String] = [:]
    private(set) var refreshing = false
    private let reader = FolderDirectoryReader()
    @ObservationIgnored private var generation = UUID()

    var rows: [Row] {
        guard let root else { return [] }
        return rows(in: root, depth: 0)
    }

    func open(_ folder: URL) async {
        if root == folder {
            await refresh()
            return
        }
        generation = UUID()
        refreshing = false
        root = folder
        children = [:]
        expanded = []
        loading = []
        errors = [:]
        await load(folder)
    }

    /// Refresh cached directories together so unchanged rows and expansion stay intact.
    func refresh() async {
        guard let root else { return }
        // A newer automatic refresh replaces any cancelled read still in flight.
        generation = UUID()
        let request = generation
        if !loading.isEmpty { loading = [] }
        refreshing = true
        defer { if request == generation { refreshing = false } }
        var updatedChildren: [URL: [FolderEntry]] = [:]
        var updatedErrors: [URL: String] = [:]
        var pending = [root]
        var visited: Set<URL> = []
        while let folder = pending.popLast() {
            guard request == generation, !Task.isCancelled else { return }
            guard visited.insert(folder).inserted else { continue }
            let entries: [FolderEntry]
            do {
                entries = try await reader.contents(of: folder)
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                // Keep the visible contents if a directory is temporarily unreadable.
                entries = children[folder] ?? []
                updatedErrors[folder] = error.localizedDescription
            }
            updatedChildren[folder] = entries
            pending += entries.filter {
                $0.canExpand && (children[$0.url] != nil || expanded.contains($0.url))
            }.map(\.url)
        }
        guard request == generation, !Task.isCancelled else { return }
        // A folder may have been expanded while the reads were suspended.
        // Merge refreshed entries into that cache before pruning removed branches.
        var mergedChildren = children.merging(updatedChildren) { _, fresh in fresh }
        var mergedErrors = errors
        for folder in visited { mergedErrors[folder] = updatedErrors[folder] }
        var reachable: Set<URL> = [root]
        var directories: Set<URL> = []
        pending = [root]
        while let folder = pending.popLast() {
            for entry in mergedChildren[folder] ?? [] where entry.canExpand {
                directories.insert(entry.url)
                if reachable.insert(entry.url).inserted { pending.append(entry.url) }
            }
        }
        mergedChildren = mergedChildren.filter { reachable.contains($0.key) }
        mergedErrors = mergedErrors.filter { reachable.contains($0.key) }
        let updatedExpanded = expanded.intersection(directories)
        if children != mergedChildren { children = mergedChildren }
        if errors != mergedErrors { errors = mergedErrors }
        if expanded != updatedExpanded { expanded = updatedExpanded }
    }

    func toggle(_ entry: FolderEntry) async {
        guard entry.canExpand else { return }
        if expanded.remove(entry.url) != nil { return }
        expanded.insert(entry.url)
        if children[entry.url] == nil { await load(entry.url) }
    }

    func load(_ folder: URL) async {
        guard !loading.contains(folder) else { return }
        let request = generation
        loading.insert(folder)
        defer { if request == generation { loading.remove(folder) } }
        if errors[folder] != nil { errors[folder] = nil }
        do {
            let entries = try await reader.contents(of: folder)
            guard request == generation, !Task.isCancelled else { return }
            if children[folder] != entries { children[folder] = entries }
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errors[folder] = error.localizedDescription
        }
    }

    private func rows(in folder: URL, depth: Int) -> [Row] {
        (children[folder] ?? []).flatMap { entry in
            [Row(entry: entry, depth: depth)]
                + (expanded.contains(entry.url) ? rows(in: entry.url, depth: depth + 1) : [])
        }
    }
}
