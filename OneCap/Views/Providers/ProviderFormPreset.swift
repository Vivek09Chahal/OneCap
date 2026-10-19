import Foundation

enum ProviderFormPreset: String, CaseIterable, Identifiable {
    case deepSeek = "DeepSeek"
    case custom = "Custom provider"
    var id: Self { self }
    var name: String { self == .deepSeek ? "DeepSeek" : "" }
    var baseURL: String { self == .deepSeek ? "https://api.deepseek.com" : "" }
    var model: String { self == .deepSeek ? "deepseek-chat" : "" }
}
