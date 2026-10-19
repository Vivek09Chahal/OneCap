import DLS
import SwiftUI

/// Anchoring the bottom edge puts composer choices above the text bar.
struct ComposerOptionsButton<Label: View, Content: View>: View {
    @State private var presented = false
    let enabled: Bool
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: (@escaping () -> Void) -> Content
    
    var body: some View {
        Button {
            presented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            content { presented = false }
        }
        .onChange(of: enabled) { _, enabled in
            if !enabled { presented = false }
        }
    }
}

struct ComposerOptionsList<Content: View>: View {
    let rowCount: Int
    let headingCount: Int
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DLSSpacing.xs) { content() }
                .padding(DLSSpacing.sm)
        }
        .frame(width: 300, height: min(380, CGFloat(rowCount * 36 + headingCount * 28 + 16)))
    }
}

struct ComposerOptionRow: View {
    @Environment(\.dlsTheme) private var theme
    @State private var hovered = false
    let title: String
    let selected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DLSSpacing.sm) {
                Text(title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark").opacity(selected ? 1 : 0)
            }
            .font(DLSTypography.callout)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, DLSSpacing.sm)
            .frame(minHeight: 32)
            .background(
                hovered ? theme.colors.composer : .clear,
                in: RoundedRectangle(cornerRadius: DLSRadius.small)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SessionOptionsList: View {
    @Environment(AppStore.self) private var store
    let options: [ACPSessionOption]
    let dismiss: () -> Void
    
    var body: some View {
        ComposerOptionsList(
            rowCount: options.reduce(0) { $0 + $1.choices.count },
            headingCount: options.count + options.reduce(0) { $0 + groups($1).count }
        ) {
            ForEach(options) { option in
                Text(option.name).font(DLSTypography.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, DLSSpacing.sm).padding(.top, DLSSpacing.xs)
                ForEach(Array(option.choices.enumerated()), id: \.offset) { index, choice in
                    if let group = choice.group,
                       index == 0 || option.choices[index - 1].group != group
                    {
                        Text(group).font(DLSTypography.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, DLSSpacing.sm)
                    }
                    ComposerOptionRow(title: choice.name, selected: option.currentValue == choice.id) {
                        dismiss()
                        Task { await store.changeSessionOption(option.id, value: choice.id) }
                    }
                }
            }
        }
    }
    
    private func groups(_ option: ACPSessionOption) -> Set<String> {
        Set(option.choices.compactMap(\.group))
    }
}
