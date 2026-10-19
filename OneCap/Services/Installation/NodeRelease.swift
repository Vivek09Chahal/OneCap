import Foundation

struct NodeRelease: Decodable {
    let version: String
    let lts: LTS
    enum LTS: Decodable {
        case active, inactive
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            self = (try? value.decode(String.self)) != nil ? .active : .inactive
        }
    }
}
