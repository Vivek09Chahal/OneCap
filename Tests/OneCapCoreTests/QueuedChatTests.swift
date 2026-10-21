import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import OneCapCore

private func queueTestImage() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
        bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@MainActor private func queuedStore(ending: String) async throws -> (AppStore, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-queue-\(UUID())").resolvingSymlinksInPath()
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json,sys,pathlib,time,threading
    root=pathlib.Path(sys.argv[1]); project=pathlib.Path(sys.argv[2]); mode=sys.argv[3]
    lock=threading.Lock(); stopped=False; active=None
    def send(o):
        with lock: print(json.dumps(dict(jsonrpc='2.0',**o)),flush=True)
    def chunk(text):
        send(dict(method='session/update',params=dict(sessionId='queue',update=dict(sessionUpdate='agent_message_chunk',content=dict(type='text',text=text)))))
    def run(m):
        global active
        text=m['params']['prompt'][-1].get('text','')
        if text=='first':
            active=m['id']; chunk('Working')
            while not (root/'release').exists() and not stopped: time.sleep(.01)
            if stopped: return
            if mode=='fail':
                send(dict(id=m['id'],error=dict(code=-32603,message='Fixture failure'))); return
        (project/'file.txt').write_text(text)
        chunk(' done:'+text)
        send(dict(id=m['id'],result=dict(stopReason='end_turn')))
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); result={}
        if method=='initialize':
            result=dict(protocolVersion=1,agentCapabilities=dict(promptCapabilities=dict(image=mode!='no-images')))
        elif method=='session/new': result=dict(sessionId='queue')
        elif method=='session/prompt':
            with (root/'prompts.jsonl').open('a') as f: f.write(json.dumps(m['params']['prompt'])+'\n')
            threading.Thread(target=run,args=(m,),daemon=True).start(); continue
        elif method=='session/cancel':
            stopped=True
            if active is not None: send(dict(id=active,result=dict(stopReason='cancelled')))
            continue
        send(dict(id=m['id'],result=result))
    """#.write(to: script, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("State/state.json"))
    await store.load()
    let agent = InstalledAgent(id: "queued-fixture", name: "Queue", version: "1", executable: "/usr/bin/python3",
        arguments: ["-u", script.path, root.path, project.path, ending], environment: [:], directory: root.path)
    store.installed = [agent]
    store.selectedAgentID = agent.id
    store.chatUsesAgent = true
    store.workspace = project
    await store.connect()
    #expect(store.acp.sessionReady)
    return (store, root)
}

@MainActor private func awaitQueue(_ condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Queue did not reach its expected state")
}

@Test(arguments: ["complete", "stop", "fail"])
@MainActor func followUpsKeepCurrentRunAndAttachmentsAndPauseOnStopOrFailure(_ ending: String) async throws {
    let (store, root) = try await queuedStore(ending: ending)
    defer { store.resetChat(); try? FileManager.default.removeItem(at: root) }
    store.send("first", useAgent: true)
    try await awaitQueue { store.messages.last?.text == "Working" }
    let activeReply = store.replyID
    let image = try queueTestImage()
    let imageURL = root.appendingPathComponent("image.png")
    try image.write(to: imageURL)
    #expect(await store.attachFiles([imageURL]))
    #expect(store.sending && store.replyID == activeReply)
    #expect(store.send("second", useAgent: true))
    let note = root.appendingPathComponent("note.txt")
    try "extra context".write(to: note, atomically: true, encoding: .utf8)
    #expect(await store.attachFiles([note]))
    #expect(store.send("third", useAgent: true))
    #expect(store.queuedMessages.map { $0.message.text } == ["second", "third"])
    #expect(store.queuedMessages.first?.message.attachments?.first?.imageData == image)
    #expect(store.messages.count == 2 && store.replyID == activeReply)
    let queuedLog = try String(contentsOf: root.appendingPathComponent("prompts.jsonl"), encoding: .utf8)
    #expect(queuedLog.split(separator: "\n").count == 1)
    store.draft = "I can keep typing"
    #expect(await store.attachFiles([note]))
    store.checkpointConversation(touch: false)
    await store.historySaveTask?.value
    let reopened = AppStore(stateURL: root.appendingPathComponent("State/state.json"))
    await reopened.load()
    reopened.openConversation(store.conversationID)
    #expect(reopened.queuedMessages.count == 2 && !reopened.sending)
    #expect(reopened.queuedMessages.first?.message.attachments?.first?.imageData == image)
    await reopened.historySaveTask?.value
    if ending == "stop" { store.stopReply() }
    else { try Data().write(to: root.appendingPathComponent("release")) }
    try await awaitQueue { !store.sending }
    #expect(store.draft == "I can keep typing" && store.draftAttachments.first?.text == "extra context")
    if ending == "complete" {
        #expect(store.queuedMessages.isEmpty)
        #expect(store.messages.filter { $0.role == "user" }.map(\.text) == ["first", "second", "third"])
        #expect(store.messages.last?.text == " done:third")
        #expect(store.fileChanges.count == 3)
        #expect(store.fileChanges.map { $0.files.first?.after } == ["first", "second", "third"])
        let log = try String(contentsOf: root.appendingPathComponent("prompts.jsonl"), encoding: .utf8)
        let prompts = try log.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [[String: Any]] }
        #expect(prompts.count == 3)
        #expect(prompts[1].contains { $0["type"] as? String == "image" && $0["data"] as? String == image.base64EncodedString() })
        #expect(prompts[2].contains { ($0["text"] as? String)?.contains("extra context") == true })
    } else {
        #expect(store.queuedMessages.count == 2)
        #expect(store.messages.last?.replyState == (ending == "stop" ? .stopped : .failed))
        let log = try String(contentsOf: root.appendingPathComponent("prompts.jsonl"), encoding: .utf8)
        #expect(log.split(separator: "\n").count == 1)
        store.removeQueuedMessage(store.queuedMessages[0].id)
        #expect(store.queuedMessages.first?.message.text == "third")
    }
    await store.historySaveTask?.value
    await store.projectSaveTask?.value
}

@Test @MainActor func unsupportedAgentImagesPreserveTheDraftInsteadOfSendingOrDiscardingIt() async throws {
    let (store, root) = try await queuedStore(ending: "no-images")
    defer { store.resetChat(); try? FileManager.default.removeItem(at: root) }
    await store.attachImage(try queueTestImage())
    store.draft = "Look at this"
    #expect(!store.send(store.draft, useAgent: true))
    #expect(store.draftAttachments.count == 1 && store.draft == "Look at this")
    #expect(store.messages.isEmpty && !store.sending)
    #expect(store.connectionError?.contains("does not support image") == true)
    await store.historySaveTask?.value
    await store.projectSaveTask?.value
}

@Test func imageAttachmentsRetainBytesValidateInputAndEncodeMultimodalProviderContent() async throws {
    let bytes = try queueTestImage()
    let importer = ChatFileImporter()
    let attachment = try await importer.image(bytes, name: "picture.png")
    #expect(attachment.mimeType == "image/png" && attachment.imageData == bytes)
    let message = ChatMessage(role: "user", text: "Describe", attachments: [attachment])
    let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
    #expect(restored.attachments?.first?.imageData == bytes)
    let blocks = try #require(restored.providerContent as? [[String: Any]])
    #expect(blocks[0]["type"] as? String == "text")
    let imageURL = try #require(blocks[1]["image_url"] as? [String: String])
    #expect(imageURL["url"] == "data:image/png;base64," + bytes.base64EncodedString())
    await #expect(throws: (any Error).self) { try await importer.image(Data([0, 255]), name: "fake.png") }
    await #expect(throws: (any Error).self) {
        try await importer.image(Data(repeating: 0, count: ChatFileImporter.maximumImageBytes + 1), name: "large.png")
    }
}
