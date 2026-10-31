import DLS
import SwiftUI

struct ComposerSlashSuggestions: View {
    @Environment(\.dlsTheme) private var theme
    let rows: [ComposerSlashSuggestion]
    @Binding var selectedIndex: Int
    let emptyMessage: String
    let choose: (ComposerSlashSuggestion) -> Void

    static func height(for count: Int) -> CGFloat { CGFloat(min(5, max(1, count))) * 48 + 16 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty {
                        Text(emptyMessage).foregroundStyle(theme.colors.textSecondary)
                            .padding(DLSSpacing.sm).frame(minHeight: 48)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { choose(row) } label: {
                            HStack(spacing: DLSSpacing.sm) {
                                Image(systemName: row.symbol).frame(width: DLSSize.iconSmall)
                                VStack(alignment: .leading, spacing: DLSSpacing.xxs) {
                                    Text(row.title).lineLimit(1)
                                    Text(row.enabled ? row.detail : "Unavailable while busy or disconnected")
                                        .dlsFont(.caption).foregroundStyle(theme.colors.textSecondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if index == selectedIndex { Image(systemName: "return") }
                            }
                            .padding(.horizontal, DLSSpacing.sm).frame(height: 48)
                            .contentShape(Rectangle())
                            .background(index == selectedIndex ? theme.colors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: DLSRadius.small))
                        }
                        .buttonStyle(.plain).focusable(false).disabled(!row.enabled)
                        .id(row.id).onHover { if $0 { selectedIndex = index } }
                        .help(row.detail)
                    }
                }
                .padding(DLSSpacing.sm)
            }
            .onChange(of: selectedIndex) {
                if rows.indices.contains(selectedIndex) { proxy.scrollTo(rows[selectedIndex].id) }
            }
        }
        .frame(height: Self.height(for: rows.count))
        .dlsFont(.callout).foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.large))
        .overlay { RoundedRectangle(cornerRadius: DLSRadius.large).stroke(theme.colors.borderStrong, lineWidth: DLSSize.border) }
        .shadow(color: .black.opacity(0.18), radius: DLSSpacing.md, y: -DLSSpacing.xs)
        .accessibilityLabel("Slash command suggestions. Use arrow keys to choose, Return or Tab to accept, Escape to dismiss.")
    }
}
