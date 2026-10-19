import DLS
import SwiftUI

struct FolderTreeRow: View {
    @Environment(\.dlsTheme) private var theme
    let entry: FolderEntry
    let depth: Int
    let expanded: Bool
    let loading: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: DLSSpacing.sm) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(DLSTypography.footnote)
                .opacity(entry.canExpand ? 1 : 0)
                .frame(width: DLSSpacing.md)
            Image(systemName: entry.symbol)
                .font(DLSTypography.navigationIcon)
                .foregroundStyle(entry.canExpand ? theme.colors.accent : theme.colors.textSecondary)
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: DLSSpacing.none)
            if loading { ProgressView().controlSize(.mini) }
        }
        .font(DLSTypography.callout)
        .padding(.leading, DLSSpacing.md + CGFloat(depth) * DLSSpacing.lg)
        .padding(.trailing, DLSSpacing.md)
        .padding(.vertical, DLSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(entry.url.path)
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
        .onTapGesture { if entry.canExpand { toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(entry.canExpand ? .isButton : [])
        .accessibilityValue(entry.canExpand ? (expanded ? "Expanded" : "Collapsed") : "File")
        .accessibilityAction { if entry.canExpand { toggle() } }
    }
}
