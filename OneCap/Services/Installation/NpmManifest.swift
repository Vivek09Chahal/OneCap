import Foundation

struct NpmManifest: Decodable { let bin: NpmExecutable }
enum NpmExecutable: Decodable {
    case path(String)
    case map([String: String])
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let path = try? container.decode(String.self) {
            self = .path(path)
        } else {
            self = .map(try container.decode([String: String].self))
        }
    }
    var entry: String? {
        switch self {
        case .path(let path): path
        case .map(let map): map.sorted { $0.key < $1.key }.first?.value
        }
    }
}
