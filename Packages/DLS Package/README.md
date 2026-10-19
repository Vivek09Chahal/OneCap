# DLS Package

A local, dependency-free SwiftUI design token package. Package name: **DLS Package**. Library product and importable module: **DLS**.

Supports macOS 14+ and iOS 17+, using Swift tools 6.2+. OneCap's deployment target remains macOS 26+.

## Token groups

| API | Purpose |
| --- | --- |
| `DLSSpacing` | Shared spacing and padding scale, from `none` to `huge` |
| `DLSRadius` | Small, medium, large, and extra-large corner radii |
| `DLSSize` | Icon, avatar, border, and letter-spacing sizes |
| `DLSTypography` | Semantic headings, body text, captions, monospaced labels, and display styles |
| `DLSColors` | Explicit light/dark palettes with matching semantic roles |
| `DLSTheme` | Selects the light or dark palette |
| `DLSAppearance` | Resolves System, Light, or Dark appearance |

Colors include background, surface, sidebar, composer, primary/secondary/tertiary text, borders, accent and its foreground, subtle/muted accent surfaces, success, warning, danger, and user-message background. The dark palette uses neutral charcoal, gray panels, burnt-orange accents, and rust-colored message bubbles. The light palette uses white and cool gray surfaces with coordinated orange accents. Content typography uses system text styles; fixed display sizes are centralized for branding and icon treatments.

## Use

Add this folder as a local Swift package dependency and link the **DLS** library to your target. The OneCap Xcode project already does this.

```swift
import DLS
import SwiftUI

struct ExampleView: View {
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.md) {
            Text("Welcome").font(DLSTypography.pageTitle)
            Text("Choose your agent.")
                .font(DLSTypography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(DLSSpacing.xxl)
        .background(theme.colors.surface,
                    in: RoundedRectangle(cornerRadius: DLSRadius.large))
    }
}

// Apply at each presentation root. The default follows system appearance.
ExampleView().dlsAppearance()
ExampleView().dlsAppearance(.light)
ExampleView().dlsAppearance(.dark)
```

The appearance modifier injects `dlsTheme`, applies the accent tint and base text styling, and coordinates native SwiftUI controls through the preferred color scheme. Components should use semantic colors from their environment, rather than inspecting appearance or choosing raw RGB values themselves.

OneCap saves its selection in `@AppStorage("appearance")` and exposes it through **Settings → Appearance**. Application-specific window sizes, column widths, and form widths remain in the app rather than becoming generic design tokens.

## Build independently

```sh
swift build --package-path 'Packages/DLS Package'
```

Run that command from the OneCap repository root. No networking or runtime installation is required for this package.
