import Foundation

/// Only choices advertised by the current agent are offered to the user.
struct ACPSessionOption: Identifiable, Equatable, Sendable {
    enum Transport: Sendable { case config, model, mode }
    struct Choice: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var group: String?
    }
    var id: String
    var name: String
    var category: String?
    var currentValue: String
    var choices: [Choice]
    var transport: Transport = .config
    
    var isModeSelector: Bool { category == "mode" || transport == .mode || id == "mode" }
    
    var selectedName: String { choices.first { $0.id == currentValue }?.name ?? currentValue }
    
    static func decode(_ result: [String: Any]) -> [Self] {
        if let configs = result["configOptions"] as? [[String: Any]] {
            return configs.compactMap { item in
                guard item["type"] as? String == "select", let id = item["id"] as? String,
                      let name = item["name"] as? String, let current = item["currentValue"] as? String,
                      let values = item["options"] as? [[String: Any]]
                        else { return nil }
                let choices = values.flatMap { value -> [Choice] in
                    if let grouped = value["options"] as? [[String: Any]] {
                        return grouped.compactMap { choice($0, group: value["name"] as? String) }
                    }
                    return choice(value).map { [$0] } ?? []
                }
                return Self(
                    id: id, name: name, category: item["category"] as? String,
                    currentValue: current, choices: choices)
            }
        }
        // Older ACP agents expose the same selectors through models/modes instead.
        return [
            legacy(result, key: "models", category: "model", transport: .model),
            legacy(result, key: "modes", category: "mode", transport: .mode),
        ].compactMap { $0 }
    }
    
    private static func choice(_ item: [String: Any], group: String? = nil) -> Choice? {
        guard let value = item["value"] as? String, let name = item["name"] as? String else {
            return nil
        }
        return Choice(id: value, name: name, group: group)
    }
    
    private static func legacy(
        _ result: [String: Any], key: String, category: String,
        transport: Transport
    ) -> Self? {
        let isModel = transport == .model
        guard let state = result[key] as? [String: Any],
              let current = state[isModel ? "currentModelId" : "currentModeId"] as? String,
              let available = state[isModel ? "availableModels" : "availableModes"] as? [[String: Any]]
                else { return nil }
        let choices = available.compactMap { item -> Choice? in
            guard let id = item[isModel ? "modelId" : "id"] as? String,
                  let name = item["name"] as? String
                    else { return nil }
            return Choice(id: id, name: name)
        }
        return Self(
            id: category, name: isModel ? "Model" : "Mode", category: category,
            currentValue: current, choices: choices, transport: transport)
    }
}
