import DLS
import SwiftUI

/// Shared template rendering and sizing for app assets and SF Symbols.
/// Inherits the caller's foreground style so labels retain native button contrast.
struct AppIcon: View {
    private let image: Image
    private let size: CGFloat

    init(_ name: String, size: CGFloat = DLSSize.iconCompact) {
        image = Image(name)
        self.size = size
    }

    init(systemName: String, size: CGFloat = DLSSize.iconCompact) {
        image = Image(systemName: systemName)
        self.size = size
    }

    var body: some View {
        image
            // Native menus otherwise apply their accent tint and intrinsic symbol size.
            .renderingMode(.template)
            .resizable()
            // Preserve SF Symbols' optical alignment and stroke weight across glyph shapes.
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
