@testable import OneCap
import AppKit
import DLS
import SwiftUI

private struct NoNetworkInstaller: AgentInstalling {
    func catalog() async throws -> Registry { Registry(version: "1", agents: []) }
    func install(_ agent: Agent) async throws -> InstalledAgent { throw AppFailure("Not used") }
    func uninstall(_ agent: InstalledAgent, repository: AppRepository) async throws -> AgentUninstallResult { throw AppFailure("Not used") }
}

@main struct FullViewRecovery {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: "/tmp/OneCap-view-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("agent.py")
        try #"""
        import json,sys
        def send(o): print(json.dumps(dict(jsonrpc='2.0',**o)),flush=True)
        for line in sys.stdin:
            m=json.loads(line); method=m.get('method'); result={}
            if method=='initialize': result=dict(protocolVersion=1,authMethods=[dict(id='login',name='Sign in',type='terminal',args=['--login'])])
            elif method=='session/new': result=dict(sessionId='fixture')
            elif method=='session/prompt':
                send(dict(method='session/update',params=dict(sessionId='fixture',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text='Failed to authenticate: OAuth session expired and could not be refreshed')))))
                send(dict(id=m['id'],error=dict(code=-32603,message='Internal error')))
                continue
            send(dict(id=m['id'],result=result))
        """#.write(to: script, atomically: true, encoding: .utf8)
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"), installer: NoNetworkInstaller())
        store.loaded = true
        store.historyLoaded = true
        store.projectsLoaded = true
        store.installed = [.init(id: "fixture", name: "Claude fixture", version: "1", executable: "/usr/bin/python3", arguments: ["-u",script.path], environment: [:], directory: root.path)]
        store.chatUsesAgent = true
        store.selectedAgentID = "fixture"
        store.projectFolders = [root]
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width:1180,height:800), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environment(store).dlsAppearance(.dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x:0,y:0,width:1180,height:800)
        window.contentView = host
        window.orderOut(nil)
        func settle() async throws {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        func ready() async throws {
            try await settle()
            if !store.acp.sessionReady && !store.connecting { await store.connect() }
            for _ in 0..<300 {
                if store.acp.sessionReady && !store.connecting { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw AppFailure("Fixture connection not ready")
        }
        try await ready()
        for index in 0..<3 {
            if index > 0 {
                store.resetChat()
                try await ready()
            }
            store.draft = "hi"
            store.send("hi", useAgent: true)
            for _ in 0..<300 {
                if !store.sending { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try await settle()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw AppFailure("No rendered view") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try verifyVisibleContent(bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/OneCap-full-view-recovery-\(index).png"))
            guard store.error == nil, store.acp.authenticationRequired, store.connectionError != nil else { throw AppFailure("Recovery state failed") }
        }
        store.resetChat()
        await store.historySaveTask?.value
        await store.projectSaveTask?.value
        window.close()
        print("Verified sidebar and composer pixels after three streamed OAuth failures; inline recovery remained available.")
    }
    @MainActor private static func verifyVisibleContent(_ bitmap: NSBitmapImageRep) throws {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var visibleHeader = false
        for y in stride(from: 0, to: Int(Double(height) * 0.12), by: 2) {
            for x in stride(from: Int(Double(width) * 0.06), to: Int(Double(width) * 0.25), by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   color.redComponent > 0.5, color.greenComponent < 0.5, color.blueComponent < 0.3 {
                    visibleHeader = true
                }
            }
        }
        let composer = bitmap.colorAt(x: Int(Double(width) * 0.65), y: height - Int(Double(height) * 0.08))?.usingColorSpace(.sRGB)
        guard visibleHeader, let composer, composer.redComponent > 0.16 else {
            throw AppFailure("Sidebar or composer disappeared after the request")
        }
    }

}
