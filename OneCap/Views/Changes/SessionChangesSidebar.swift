import DLS
import SwiftUI

struct SessionChangesSidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.none) {
            HStack {
                Text("Chat changes").dlsFont(.captionStrong)
                Spacer()
                Text("\(Set(store.fileChanges.flatMap { $0.files.map(\.path) }).count) files")
                    .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary)
            }
            .padding(DLSSpacing.md)
            Divider()
            if store.fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    Text("No edits yet").dlsFont(.heading)
                    Text("Files changed during agent replies will appear here.")
                        .dlsFont(.callout).foregroundStyle(theme.colors.textSecondary)
                }
                .padding(DLSSpacing.lg)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DLSSpacing.lg) {
                        ForEach(store.fileChanges.reversed()) { changes in
                            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                                Button { store.reviewFileChanges(changes) } label: {
                                    HStack {
                                        Text(changes.revertedAt == nil ? "Edited \(changes.files.count) files" : "Changes undone")
                                            .dlsFont(.captionStrong)
                                        Spacer()
                                        FileChangeCounts(additions: changes.additions, deletions: changes.deletions)
                                    }
                                }
                                .buttonStyle(.plain)
                                Text(changes.createdAt, style: .time)
                                    .dlsFont(.footnote).foregroundStyle(theme.colors.textSecondary)
                                ForEach(changes.files) { file in
                                    Button { store.reviewFileChanges(changes, path: file.path) } label: {
                                        Label(file.path, systemImage: file.after == nil ? "minus.circle" : "doc")
                                            .lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .dlsFont(.callout).buttonStyle(.plain).help(file.path)
                                }
                            }
                            Divider()
                        }
                    }
                    .padding(DLSSpacing.md)
                }
            }
        }
        .foregroundStyle(theme.colors.textPrimary).background(theme.colors.sidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.colors.borderStrong).frame(width: DLSSize.border)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
