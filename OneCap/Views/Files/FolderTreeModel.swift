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
    private let reader = FolderDirectoryReader()
    private var generation = UUID()

    var rows: [Row] {
        guard let root else { return [] }
        return rows(in: root, depth: 0)
    }

    func open(_ folder: URL) async {
        generation = UUID()
        root = folder
        children = [:]
        expanded = []
        loading = []
        errors = [:]
        await load(folder)
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
        errors[folder] = nil
        do {
            let entries = try await reader.contents(of: folder)
            guard request == generation, !Task.isCancelled else { return }
            children[folder] = entries
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errors[folder] = error.localizedDescription
        }
        if request == generation { loading.remove(folder) }
    }

    private func rows(in folder: URL, depth: Int) -> [Row] {
        (children[folder] ?? []).flatMap { entry in
            [Row(entry: entry, depth: depth)]
                + (expanded.contains(entry.url) ? rows(in: entry.url, depth: depth + 1) : [])
        }
    }
}
