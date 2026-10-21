import DLS
import SwiftUI

/// Native, checked menu choices with a compact label shared by toolbar selectors.
struct ToolbarSelectionMenu<Selection: Hashable, Options: View>: View {
    let title: String
    let selectedTitle: String
    let symbol: String
    @Binding var selection: Selection
    var labelFont: Font = DLSTypography.toolbarLabel
    var selectedImage: Image? = nil
    var flexibleLabel = false
    var unifiedForeground = false
    var labelColor: Color? = nil
    @ViewBuilder var options: () -> Options
    @Environment(\.dlsTheme) private var theme

    private var accessoryColor: Color {
        unifiedForeground ? (labelColor ?? theme.colors.textPrimary) : theme.colors.textSecondary
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options() }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            // Inline symbols prevent AppKit from rearranging the menu label.
            // Raster logos need a lower baseline; SF Symbols already carry alignment metrics.
            Text("\(Text(selectedImage ?? Image(systemName: symbol)).baselineOffset(selectedImage == nil ? 0 : -DLSSpacing.xs).foregroundStyle(accessoryColor))  \(Text(selectedTitle))  \(Text(Image(systemName: "chevron.down")).font(DLSTypography.footnote).foregroundStyle(accessoryColor))")
                .font(labelFont)
                .foregroundStyle(labelColor ?? theme.colors.textPrimary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: !flexibleLabel, vertical: false)
                .padding(.horizontal, DLSSpacing.xs)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(title): \(selectedTitle)")
    }
}
