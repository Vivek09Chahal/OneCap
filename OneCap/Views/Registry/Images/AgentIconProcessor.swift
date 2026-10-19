import AppKit
import Kingfisher

/// Rasterize remote registry SVGs at the display scale for Kingfisher's PNG cache.
/// macOS supplies SVG decoding; no bundled logos or additional SVG library is needed.
struct AgentIconProcessor: ImageProcessor {
    let pointSize: CGFloat
    let scale: CGFloat

    var identifier: String { "dev.onecap.agent-icon.v1.\(pointSize).\(scale)" }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> NSImage? {
        let image: NSImage
        switch item {
        case .image(let input): image = input
        case .data(let data):
            guard data.count <= 2 * 1024 * 1024, let decoded = NSImage(data: data) else { return nil }
            image = decoded
        }
        guard image.size.width > 0, image.size.height > 0,
              pointSize > 0, scale > 0, pointSize * scale <= 512 else { return nil }
        let pixels = Int(ceil(pointSize * scale))
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let ratio = min(CGFloat(pixels) / image.size.width, CGFloat(pixels) / image.size.height)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        image.draw(in: CGRect(x: (CGFloat(pixels) - size.width) / 2,
                              y: (CGFloat(pixels) - size.height) / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1)
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: CGSize(width: pointSize, height: pointSize))
    }
}
