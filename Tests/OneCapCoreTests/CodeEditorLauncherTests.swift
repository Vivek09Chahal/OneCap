import Foundation
import Testing

@testable import OneCapCore

@Test @MainActor func editorDiscoveryOnlyListsInstalledAppsAndDeduplicatesPaths() {
    let code = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    let zed = URL(fileURLWithPath: "/Applications/Zed.app")
    let editors = CodeEditorLauncher.installedEditors { identifier in
        switch identifier {
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders": code
        case "dev.zed.Zed": zed
        default: nil
        }
    }
    #expect(editors.map(\.name) == ["VS Code", "Zed"])
    #expect(editors.map(\.applicationURL) == [code, zed])
    #expect(CodeEditorLauncher.installedEditors(resolve: { _ in nil }).isEmpty)
}

@Test @MainActor func openingMissingEditorTargetFailsBeforeLaunchingAnApplication() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let editor = InstalledCodeEditor(name: "Fixture", applicationURL: missing.appendingPathComponent("Editor.app"))
    await #expect(throws: (any Error).self) {
        try await CodeEditorLauncher.open(missing, in: editor)
    }
    #expect(CodeEditorLauncher.editor(at: missing) == nil)
}
