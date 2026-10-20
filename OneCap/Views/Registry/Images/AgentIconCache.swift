import AppKit
import Foundation
import Kingfisher

@MainActor enum AgentIconCache {
    static let images: ImageCache = {
        let cache = ImageCache(name: "agent-icons")
        cache.memoryStorage.config.totalCostLimit = 16 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 128
        cache.diskStorage.config.sizeLimit = 50 * 1024 * 1024
        return cache
    }()
    static func image(at url: URL, pointSize: CGFloat, scale: CGFloat) async throws -> NSImage {
        let result = try await KingfisherManager.shared.retrieveImage(with: url, options: [
            .targetCache(images), .originalCache(images), .cacheOriginalImage,
            .processor(AgentIconProcessor(pointSize: pointSize, scale: scale)),
            .processingQueue(.dispatch(processing)),
            .memoryCacheExpiration(.days(7)), .diskCacheExpiration(.days(30)),
        ])
        // PNG cache hits can restore pixel dimensions as point dimensions.
        // Normalize a copy so inline text attachments keep the same size on every load.
        guard let image = result.image.copy() as? NSImage else { return result.image }
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }

    static let processing = DispatchQueue(label: "dev.onecap.agent-icons", qos: .utility)
}
