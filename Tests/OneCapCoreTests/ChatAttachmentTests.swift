import Foundation
import PDFKit
import Testing

@testable import OneCapCore

@Test func fileImporterReadsTextAndRejectsBinaryOversizeAndTooManyFiles() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-files-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("Example.swift")
  try Data("let answer = 42".utf8).write(to: source)
  let importer = ChatFileImporter()
  let files = try await importer.read([source])
  #expect(files.first?.name == "Example.swift")
  #expect(files.first?.text == "let answer = 42")
  let binary = root.appendingPathComponent("image.png")
  try Data([0, 255, 2]).write(to: binary)
  let large = root.appendingPathComponent("large.txt")
  try Data(repeating: 65, count: ChatFileImporter.maximumBytes + 1).write(to: large)
  for urls in [[binary], [large], Array(repeating: source, count: 6), [root]] {
    await #expect(throws: (any Error).self) { try await importer.read(urls) }
  }
}

@Test @MainActor func fileDraftsSurviveFolderSelectionAndHistoryReloadAndCanBeRemoved() async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-file-history-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("Notes.txt")
  try Data("Important notes".utf8).write(to: source)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  await store.load()
  await store.attachFiles([source])
  #expect(store.draftAttachments.first?.text == "Important notes")
  store.selectWorkspace(root)
  #expect(store.draftAttachments.count == 1)
  store.checkpointConversation()
  let id = store.conversationID
  await store.historySaveTask?.value
  await store.projectSaveTask?.value
  let reopened = AppStore(stateURL: root.appendingPathComponent("state.json"))
  await reopened.load()
  reopened.openConversation(id)
  #expect(reopened.draftAttachments.first?.name == "Notes.txt")
  let file = try #require(reopened.draftAttachments.first)
  reopened.removeAttachment(file.id)
  #expect(reopened.draftAttachments.isEmpty)
  #expect(!reopened.conversations.contains(where: { $0.id == id }))
  await reopened.historySaveTask?.value
  await reopened.projectSaveTask?.value
}

@Test func attachmentsAreIncludedInProviderAndRestoredContextAndLegacyChatsStillDecode() throws {
  let message = ChatMessage(
    role: "user", text: "Review this",
    attachments: [.init(name: "code.swift", text: "let value = 42")])
  #expect(message.contentForModel.contains("let value = 42"))
  #expect(message.contentForModel.contains("code.swift"))
  let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
  #expect(restored.contentForModel == message.contentForModel)
  let legacy = Data("{\"id\":\"\(UUID())\",\"role\":\"user\",\"text\":\"Hello\"}".utf8)
  #expect(try JSONDecoder().decode(ChatMessage.self, from: legacy).attachments == nil)
}

@Test @MainActor func acpReceivesAttachedFileContentsWithThePrompt() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "OneCap-file-acp-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let script = root.appendingPathComponent("agent.py")
  try #"""
  import json, sys
  for line in sys.stdin:
      m=json.loads(line); method=m.get('method'); result={}
      if method=='initialize': result={'protocolVersion':1}
      elif method=='session/new': result={'sessionId':'files'}
      elif method=='session/prompt':
          blocks=m['params']['prompt']
          ok=any('let value = 42' in b.get('text','') and 'code.swift' in b.get('text','') for b in blocks)
          ok=ok and blocks[-1]['text']=='Review this'
          print(json.dumps({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'files','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'File received' if ok else 'File missing'}}}}),flush=True)
          result={'stopReason':'end_turn'}
      print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':result}),flush=True)
  """#.write(to: script, atomically: true, encoding: .utf8)
  let agent = InstalledAgent(
    id: "files", name: "Files", version: "1", executable: "/usr/bin/python3",
    arguments: ["-u", script.path], environment: [:], directory: root.path)
  let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
  store.installed = [agent]
  store.selectedAgentID = agent.id
  store.chatUsesAgent = true
  await store.connect()
  defer { store.resetChat() }
  store.draftAttachments = [.init(name: "code.swift", text: "let value = 42")]
  store.send("Review this", useAgent: true)
  for _ in 0..<300 {
    if !store.sending { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(!store.sending)
  #expect(store.messages.last?.text == "File received")
  #expect(store.messages.first?.attachments?.first?.name == "code.swift")
  #expect(store.draftAttachments.isEmpty)
}

@Test func pdfAttachmentsPreservePreviewDataAndExtractText() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-pdf-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let pdf = PDFDocument()
  let page = PDFPage()
  page.setBounds(CGRect(x: 0, y: 0, width: 300, height: 300), for: .mediaBox)
  pdf.insert(page, at: 0)
  let data = try #require(pdf.dataRepresentation())
  let url = root.appendingPathComponent("Preview.pdf")
  try data.write(to: url)
  let importer = ChatFileImporter()
  let attachments = try await importer.read([url])
  let attachment = try #require(attachments.first)
  #expect(attachment.pdfData == data)
  #expect(!attachment.isImage)
  #expect(attachment.mimeType == "application/pdf")
  #expect(attachment.text == "This PDF has no extractable text.")
  let restored = try JSONDecoder().decode(ChatAttachment.self, from: JSONEncoder().encode(attachment))
  #expect(restored.pdfData == data)
  #expect(ChatAttachment.context([restored]).contains("Preview.pdf"))

  let invalid = root.appendingPathComponent("Invalid.pdf")
  try Data("not a PDF".utf8).write(to: invalid)
  await #expect(throws: (any Error).self) { try await importer.read([invalid]) }
  try Data(repeating: 65, count: ChatFileImporter.maximumPDFBytes + 1).write(to: invalid)
  await #expect(throws: (any Error).self) { try await importer.read([invalid]) }
}
