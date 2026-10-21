import DLS
import SwiftUI

/// Shared spacing for history actions, folders, and conversation rows.
enum HistoryLayout {
    static let rowHeight = DLSSize.toolbarButton - DLSSpacing.xs
    static let horizontalInset = DLSSpacing.sm
    static let itemSpacing = DLSSpacing.xs
    // The native disclosure group supplies the rest of the child indentation.
    static let childInset = DLSSpacing.xs
    static let rowInsets = EdgeInsets(
        top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
}

struct HistorySectionHeading<Action: View>: View {
    let title: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: HistoryLayout.itemSpacing) {
            Text(title)
                .font(DLSTypography.historySection)
                .fontWeight(.regular)
            Spacer(minLength: DLSSpacing.sm)
            action()
        }
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
