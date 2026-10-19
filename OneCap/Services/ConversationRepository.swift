import Foundation

/// Local transcript storage shares the atomic JSON snapshot implementation.
typealias ConversationRepository = JSONFileRepository<[ChatConversation]>
