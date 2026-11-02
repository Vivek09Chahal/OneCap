import DLS
import SwiftUI

/// Shared spacing for history actions, folders, and conversation rows.
enum HistoryLayout {
    static let rowHeight = DLSSize.toolbarButton
    static let horizontalInset = DLSSpacing.sm
    static let itemSpacing = DLSSpacing.xs
    // The native disclosure group supplies the rest of the child indentation.
    static let childInset = DLSSpacing.xs
    // Native section headings add six points beyond the list's horizontal inset.
    static let headingInset = horizontalInset + DLSSpacing.sm - DLSSpacing.xxs
    // Match a disclosure child: twelve native points plus our child inset.
    static let standaloneChatInset = DLSSpacing.md + childInset
    static let rowInsets = EdgeInsets(
        top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
    // macOS sidebar lists reserve another 16 points after disclosure labels.
    // Compensate so their actions share the standalone toolbar's trailing inset.
    static let projectRowInsets = EdgeInsets(
        top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset - 16)
    // Native section headings have a two-point trailing inset instead of rowInsets.
    static let sectionActionInset = horizontalInset - 2
}

/// A shared canvas keeps sidebar actions centered on the same trailing column.
struct HistoryActionIcon: View {
    private let icon: AppIcon

    init(_ name: String) {
        icon = AppIcon(name, size: DLSSize.iconSmall)
    }

    init(systemName: String, size: CGFloat = DLSSize.iconSmall) {
        icon = AppIcon(systemName: systemName, size: size)
    }

    var body: some View {
        icon
            .frame(width: HistoryLayout.rowHeight, height: HistoryLayout.rowHeight)
            .contentShape(Rectangle())
    }
}

struct HistorySectionHeading<Action: View>: View {
    @Environment(\.dlsTheme) private var theme
    let title: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: HistoryLayout.itemSpacing) {
            Text(title)
                .dlsFont(.historySection)
                .fontWeight(.regular)
            Spacer(minLength: DLSSpacing.sm)
            action()
                .padding(.trailing, HistoryLayout.sectionActionInset)
        }
        .foregroundStyle(theme.colors.textTertiary)
        .padding(.top, DLSSpacing.md)
        .frame(minHeight: HistoryLayout.rowHeight)
        .listRowInsets(HistoryLayout.rowInsets)
    }
}

extension HistorySectionHeading where Action == EmptyView {
    init(_ title: String) {
        self.title = title
        self.action = { EmptyView() }
    }
}
