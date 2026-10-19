import Foundation

struct ACPRequestError: LocalizedError, Sendable {
    let code: Int
    let message: String
    let authenticationDetail: String?

    init(code: Int, message: String, authenticationDetail: String? = nil) {
        self.code = code
        self.message = message
        self.authenticationDetail = authenticationDetail
    }

    init(json: [String: Any]) {
        code = json["code"] as? Int ?? -32603
        message = json["message"] as? String ?? "Agent request failed."
        authenticationDetail = Self.detail(in: json["data"], depth: 0)
    }

    var authenticationRequired: Bool {
        code == -32000 || ACPAuthenticationFailure.matches(message)
            || authenticationDetail.map(ACPAuthenticationFailure.matches) == true
    }
    var errorDescription: String? { message }

    private static func detail(in value: Any?, depth: Int) -> String? {
        guard depth < 4 else { return nil }
        if let text = value as? String { return text }
        guard let object = value as? [String: Any] else { return nil }
        return ["errorKind", "message", "details", "detail", "error"].compactMap {
            detail(in: object[$0], depth: depth + 1)
        }.joined(separator: "\n")
    }
}
