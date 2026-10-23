import DLS
import SwiftUI

struct ProjectFileSuggestions: View {
    @Environment(\.dlsTheme) private var theme
    let files: [FolderEntry]
    let folder: URL
    let query: String
    @Binding var selectedIndex: Int
    let loading: Bool
    let error: String?
    let choose: (FolderEntry) -> Void

    static func height(for count: Int) -> CGFloat {
        min(288, CGFloat(max(1, count)) * 36 + 16)
    }

    var body: some View {
        VStack(spacing: DLSSpacing.none) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSSpacing.xxs) {
                        if query.isEmpty {
                            Text("Search the file name")
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(DLSSpacing.sm)
                        } else if loading && files.isEmpty {
                            HStack { ProgressView().controlSize(.mini); Text("Searching project files and folders…") }
                                .padding(DLSSpacing.sm)
                        } else if files.isEmpty {
                            Text(error ?? "No matching files or folders")
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(DLSSpacing.sm)
                        }
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            Button { choose(file) } label: {
                                HStack(spacing: DLSSpacing.sm) {
                                    Image(systemName: file.symbol).foregroundStyle(theme.colors.textSecondary)
                                    Text(file.name).lineLimit(1)
                                    Text(file.relativePath(in: folder)).foregroundStyle(theme.colors.textSecondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: DLSSpacing.xs)
                                    if index == selectedIndex { Image(systemName: "return").foregroundStyle(theme.colors.textSecondary) }
                                }
                                .padding(.horizontal, DLSSpacing.sm).frame(height: 34)
                                .contentShape(Rectangle())
                                .background(index == selectedIndex ? theme.colors.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: DLSRadius.small))
                            }
                            .buttonStyle(.plain).focusable(false).id(file.id)
                            .onHover { if $0 { selectedIndex = index } }
                            .help(file.relativePath(in: folder))
                        }
                    }
                    .padding(DLSSpacing.sm)
                }
                .onChange(of: selectedIndex) {
                    if files.indices.contains(selectedIndex) { proxy.scrollTo(files[selectedIndex].id) }
                }
            }
        }
        .frame(height: Self.height(for: files.count))
        .font(DLSTypography.callout).foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DLSRadius.large))
        .overlay { RoundedRectangle(cornerRadius: DLSRadius.large).stroke(theme.colors.borderStrong, lineWidth: DLSSize.border) }
        .shadow(color: .black.opacity(0.18), radius: DLSSpacing.md, y: -DLSSpacing.xs)
        .accessibilityLabel("Project files and folders")
    }
}
