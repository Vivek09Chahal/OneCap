import DLS
import SwiftUI

struct FolderTreeRow: View {
    @Environment(\.dlsTheme) private var theme
    let entry: FolderEntry
    let depth: Int
    let expanded: Bool
    let loading: Bool
    let activate: () -> Void

    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            Image(systemName: expanded ? "arrow.down" : "arrow.right")
                .dlsFont(.footnote)
                .opacity(entry.canExpand ? 1 : 0)
                .frame(width: DLSSpacing.md)
            Image(systemName: entry.symbol)
                .font(DLSTypography.navigationIcon)
                .foregroundStyle(theme.colors.textSecondary)
            Text(entry.name).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(entry.name.hasPrefix(".") ? theme.colors.textSecondary : theme.colors.textPrimary)
            Spacer(minLength: DLSSpacing.none)
            if loading { ProgressView().controlSize(.mini) }
            else if !entry.isDirectory, !entry.url.pathExtension.isEmpty {
                Text(entry.url.pathExtension.lowercased())
                    .dlsFont(.footnote).foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .dlsFont(.callout)
        .padding(.leading, DLSSpacing.md + CGFloat(depth) * DLSSpacing.lg)
        .padding(.trailing, DLSSpacing.md)
        .padding(.vertical, DLSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(entry.url.path)
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
        .onTapGesture { activate() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(entry.canExpand ? (expanded ? "Expanded" : "Collapsed") : "File")
        .accessibilityAction { activate() }
    }
}
