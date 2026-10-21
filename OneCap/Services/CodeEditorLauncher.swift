import AppKit
import Foundation

struct InstalledCodeEditor: Identifiable, Equatable, Sendable {
    let name: String
    let applicationURL: URL
    var id: String { applicationURL.path }
}

@MainActor enum CodeEditorLauncher {
    static func installedEditors(
        resolve: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) -> [InstalledCodeEditor] {
        let candidates = [
            ("VS Code", "com.microsoft.VSCode"),
            ("VS Code Insiders", "com.microsoft.VSCodeInsiders"),
            ("Cursor", "com.todesktop.230313mzl4w4u92"),
            ("Windsurf", "com.exafunction.windsurf"),
            ("Antigravity", "com.google.antigravity"),
            ("Zed", "dev.zed.Zed"),
            ("Zed Preview", "dev.zed.Zed-Preview"),
            ("VSCodium", "com.vscodium"),
            ("Sublime Text", "com.sublimetext.4"),
            ("Nova", "com.panic.Nova"),
            ("BBEdit", "com.barebones.bbedit"),
            ("IntelliJ IDEA", "com.jetbrains.intellij"),
            ("IntelliJ IDEA CE", "com.jetbrains.intellij.ce"),
            ("PyCharm", "com.jetbrains.pycharm"),
            ("WebStorm", "com.jetbrains.WebStorm"),
            ("Xcode", "com.apple.dt.Xcode"),
        ]
        var seen = Set<URL>()
        return candidates.compactMap { name, identifier in
            guard let url = resolve(identifier)?.standardizedFileURL, seen.insert(url).inserted else { return nil }
            return InstalledCodeEditor(name: name, applicationURL: url)
        }
    }

    static func editor(at url: URL) -> InstalledCodeEditor? {
        guard let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledCodeEditor(name: name, applicationURL: url.standardizedFileURL)
    }

    static func open(_ url: URL, in editor: InstalledCodeEditor) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppFailure("This file or project folder no longer exists on this Mac.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: editor.applicationURL, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
