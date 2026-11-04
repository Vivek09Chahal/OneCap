import Foundation

/// A sendable JSON value keeps MCP schemas intact across concurrency boundaries.
enum PluginJSON: Codable, Sendable, Equatable {
    case object([String: PluginJSON]), array([PluginJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([String: PluginJSON].self) { self = .object(v) }
        else { self = .array(try value.decode([PluginJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
    subscript(_ key: String) -> PluginJSON? {
        guard case .object(let v) = self else { return nil }; return v[key]
    }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var array: [PluginJSON]? { if case .array(let v) = self { v } else { nil } }
    var foundation: Any {
        switch self {
        case .object(let v): v.mapValues(\.foundation)
        case .array(let v): v.map(\.foundation)
        case .string(let v): v
        case .number(let v): v
        case .bool(let v): v
        case .null: NSNull()
        }
    }
}
