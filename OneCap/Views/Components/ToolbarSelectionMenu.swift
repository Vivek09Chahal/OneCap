import DLS
import SwiftUI

/// Native, checked menu choices with a compact label shared by toolbar selectors.
struct ToolbarSelectionMenu<Selection: Hashable, Options: View>: View {
    let title: String
    let selectedTitle: String
    let symbol: String
    @Binding var selection: Selection
    var labelFont: Font = DLSTypography.toolbarLabel
    @ViewBuilder var options: () -> Options
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options() }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            // Inline symbols prevent AppKit from rearranging the menu label.
            Text("\(Text(Image(systemName: symbol)).foregroundStyle(theme.colors.textSecondary))  \(Text(selectedTitle))  \(Text(Image(systemName: "chevron.down")).font(DLSTypography.footnote).foregroundStyle(theme.colors.textSecondary))")
                .font(labelFont)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, DLSSpacing.xs)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(title): \(selectedTitle)")
    }
}
