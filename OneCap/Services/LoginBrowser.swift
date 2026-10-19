import AppKit
import Foundation

enum LoginURL {
    static func validated(_ text: String) -> URL? {
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
                else { return nil }
        let local = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard url.scheme == "https" || (url.scheme == "http" && local) else { return nil }
        return url
    }
}

@MainActor enum LoginBrowser {
    static func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}
