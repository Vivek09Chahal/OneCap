import SwiftUI

struct DotGridBackground: View {
    let base: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var dots = Path()
            for x in stride(from: 10.0, to: size.width, by: 24) {
                for y in stride(from: 10.0, to: size.height, by: 24) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.25)))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
