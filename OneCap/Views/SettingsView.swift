import DLS
import SwiftUI

struct SettingsView: View {
    @Environment(\.dlsTheme) private var theme
    @AppStorage("appearance") private var appearance: DLSAppearance = .system
    @State private var section: Section = .appearance
    @State private var sidebarVisible = true

    private enum Section: String, CaseIterable {
        case appearance = "Appearance"
        case storage = "Storage"
        case about = "About"
        var symbol: String {
            switch self {
            case .appearance: "sun.max"
            case .storage: "internaldrive"
            case .about: "info.circle"
            }
        }
        var subtitle: String {
            switch self {
            case .appearance: "Personalize how OneCap looks on your Mac."
            case .storage: "Review local storage and where OneCap keeps its files."
            case .about: "About OneCap and the installed version."
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSSpacing.xxl) {
                        Text("Settings").font(DLSTypography.heading)
                            .padding(.horizontal, DLSSpacing.sm)
                        VStack(spacing: DLSSpacing.xs) {
                            ForEach(Section.allCases, id: \.self) { item in
                                sectionButton(item)
                            }
                        }
                    }
                    .padding(DLSSpacing.lg)
                }
                .frame(width: 200)
                .frame(maxHeight: .infinity)
                .background(theme.colors.sidebar)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DLSSpacing.xxl) {
                    ManagementPageHeader(title: section.rawValue, subtitle: section.subtitle)
                    switch section {
                    case .appearance: AppearanceSettingsView(appearance: $appearance)
                    case .storage: StorageSettingsView()
                    case .about: AboutSettingsView()
                    }
                }
                .frame(maxWidth: ProvidersLayout.contentWidth)
                .frame(maxWidth: .infinity)
                .padding(DLSSpacing.xxxl)
            }
        }
        .background(theme.colors.background)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(id: "settings-sidebar-toggle", placement: .navigation) {
                ToolbarIconButton(title: "Toggle settings sidebar", symbol: "sidebar.left") {
                    sidebarVisible.toggle()
                }
                .help(sidebarVisible ? "Hide settings sidebar" : "Show settings sidebar")
                .accessibilityValue(sidebarVisible ? "Visible" : "Hidden")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func sectionButton(_ item: Section) -> some View {
        Button {
            section = item
        } label: {
            Label(item.rawValue, systemImage: item.symbol)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DLSSpacing.sm)
                .background(section == item ? theme.colors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: DLSRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-section-\(item.rawValue.lowercased())")
        .accessibilityAddTraits(section == item ? .isSelected : [])
        .help(item.rawValue)
    }
}
