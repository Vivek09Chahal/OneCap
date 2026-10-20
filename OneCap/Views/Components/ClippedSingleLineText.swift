import DLS
import SwiftUI

/// Clips overflowing text with a trailing fade while leaving short titles intact.
struct ClippedSingleLineText: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var fullTextWidth: CGFloat = 0
    let text: String
    let fadeWidth: CGFloat

    init(_ text: String, fadeWidth: CGFloat = DLSSpacing.xxl) {
        self.text = text
        self.fadeWidth = fadeWidth
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        fullTextWidth = $0
                    }
            }
            .clipped()
            .mask {
                GeometryReader { geometry in
                    if fullTextWidth > geometry.size.width + 0.5, geometry.size.width > 0 {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: max(0, 1 - fadeWidth / geometry.size.width)),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                            endPoint: layoutDirection == .rightToLeft ? .leading : .trailing)
                    } else {
                        Rectangle()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
