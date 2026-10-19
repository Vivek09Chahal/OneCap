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
    static let processing = DispatchQueue(label: "dev.onecap.agent-icons", qos: .utility)
}
