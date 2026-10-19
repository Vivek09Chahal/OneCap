import DLS
import SwiftUI

struct SessionChangesSidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.none) {
            HStack {
                Text("Chat changes").font(DLSTypography.captionStrong)
                Spacer()
                Text("\(Set(store.fileChanges.flatMap { $0.files.map(\.path) }).count) files")
                    .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
            }
            .padding(DLSSpacing.md)
            Divider()
            if store.fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                    Text("No edits yet").font(DLSTypography.heading)
                    Text("Files changed during agent replies will appear here.")
                        .font(DLSTypography.callout).foregroundStyle(theme.colors.textSecondary)
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
                                            .font(DLSTypography.captionStrong)
                                        Spacer()
                                        FileChangeCounts(additions: changes.additions, deletions: changes.deletions)
                                    }
                                }
                                .buttonStyle(.plain)
                                Text(changes.createdAt, style: .time)
                                    .font(DLSTypography.footnote).foregroundStyle(theme.colors.textSecondary)
                                ForEach(changes.files) { file in
                                    Button { store.reviewFileChanges(changes, path: file.path) } label: {
                                        Label(file.path, systemImage: file.after == nil ? "doc.badge.minus" : "doc")
                                            .lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .font(DLSTypography.callout).buttonStyle(.plain).help(file.path)
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
