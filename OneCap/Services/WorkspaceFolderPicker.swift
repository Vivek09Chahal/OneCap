import AppKit

@MainActor enum WorkspaceFolderPicker {
    static func chooseFiles(
        prompt: String = "Attach files",
        message: String = "Choose text or code files (up to 256 KB each).",
        allowsFolders: Bool = false
    ) async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = allowsFolders
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        panel.message = message
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }
        }
    }
    
    static func choose() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use folder"
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
