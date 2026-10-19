import Foundation

/// Some adapters report credential expiry as an internal error instead of ACP's
/// auth-required code. Match specific credential failures, not quota/network errors.
enum ACPAuthenticationFailure {
    static func matches(_ message: String) -> Bool {
        let message = message.lowercased()
        return [
            "oauth session expired", "oauth token has expired", "oauth token expired",
            "refresh token has expired", "refresh token expired", "refresh token is invalid",
            "refresh token has been revoked", "not logged in", "please run /login",
            "authentication required", "invalid authentication credentials",
            "authentication_failed", "auth_required",
        ].contains(where: message.contains)
    }

    /// Only interpret streamed text when a request also failed. A successful
    /// answer discussing OAuth must remain a normal assistant answer.
    static func isStreamedLoginFailure(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (text.hasPrefix("failed to authenticate:") || text.hasPrefix("not logged in")
            || text.hasPrefix("session expired")) && matches(text)
    }

    static func isRequired(_ error: Error) -> Bool {
        if let error = error as? ACPRequestError { return error.authenticationRequired }
        return matches(error.localizedDescription)
    }
}
