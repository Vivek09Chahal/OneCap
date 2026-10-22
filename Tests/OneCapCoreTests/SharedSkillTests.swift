import Foundation
import Testing

@testable import OneCapCore

@Test func sharedSkillScopesIncludeSubfoldersButNotSiblingProjects() {
    let root = URL(fileURLWithPath: "/Projects/DSA")
    var skill = SharedSkill(name: "dsa", file: root.appendingPathComponent("SKILL.md"), project: root)
    #expect(skill.applies(to: root))
    #expect(skill.applies(to: root.appendingPathComponent("Trees")))
    #expect(!skill.applies(to: URL(fileURLWithPath: "/Projects/DSA-other")))
    #expect(!skill.applies(to: nil))
    skill.enabled = false
    #expect(!skill.applies(to: root))
    #expect(SharedSkill(name: "global", file: skill.file, project: nil).applies(to: nil))
}

@Test func skillFilesCreateImportEditAndRejectOverwritingExistingSkills() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = SkillFiles(globalDirectory: root.appendingPathComponent("Global"))
    let project = root.appendingPathComponent("DSA")
    let original = "---\nname: dsa-context\ndescription: DSA conventions\n---\nUse Swift for DSA exercises."
    let skill = try await files.create(name: "dsa-context", text: original, project: project)
    #expect(skill.file.path.hasSuffix("DSA/.onecap/skills/dsa-context/SKILL.md"))
    let imported = try await files.imported(skill.file.deletingLastPathComponent(), project: project)
    #expect(imported.name == "dsa-context" && imported.file == skill.file.resolvingSymlinksInPath())
    await #expect(throws: (any Error).self) {
        _ = try await files.create(name: "dsa-context", text: "Do not overwrite", project: project)
    }
    #expect(try await files.read(skill) == original)
    try await files.save(skill, text: "Use Swift and explain complexity.")
    #expect(try await files.read(skill) == "Use Swift and explain complexity.")
    await #expect(throws: (any Error).self) {
        _ = try await files.create(name: "../escape", text: "Invalid", project: project)
    }
    await #expect(throws: (any Error).self) {
        try await files.save(skill, text: String(repeating: "a", count: ChatFileImporter.maximumBytes + 1))
    }
}

@Test @MainActor func skillsPersistWithoutDuplicatesAndRemovingKeepsTheSourceFile() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let state = root.appendingPathComponent("state.json")
    let store = AppStore(stateURL: state)
    var skill = try await store.skillFiles.create(name: "global-context", text: "Shared instructions", project: nil)
    try await store.saveSkill(skill)
    let imported = try await store.skillFiles.imported(skill.file, project: nil)
    try await store.saveSkill(imported)
    #expect(store.skills.count == 1 && store.skills.first?.id == skill.id)
    skill.enabled = false
    try await store.saveSkill(skill)
    let reopened = AppStore(stateURL: state)
    try await reopened.loadSkills()
    #expect(reopened.skills.first?.enabled == false)
    try await reopened.removeSkill(try #require(reopened.skills.first))
    #expect(FileManager.default.fileExists(atPath: skill.file.path))
    let again = AppStore(stateURL: state)
    try await again.loadSkills()
    #expect(again.skills.isEmpty)
}

@Test @MainActor func corruptSkillRegistrationsArePreservedRatherThanOverwritten() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("skills.json")
    let original = Data("Invalid JSON".utf8)
    try original.write(to: file)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    await #expect(throws: (any Error).self) { try await store.loadSkills() }
    #expect(!store.skillsLoaded)
    #expect(try Data(contentsOf: file) == original)
}

@Test func sharedSkillContextWorksWithProviderMessagesAndDeduplicatesPaths() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = SkillFiles(globalDirectory: root)
    let skill = try await files.create(name: "conventions", text: "Explain time and space complexity.", project: nil)
    var sameFile = skill
    sameFile.id = UUID()
    let context = try await files.context([skill, sameFile], workspace: nil)
    #expect(context.count == 1)
    let outgoing = ChatMessage(role: "user", text: "Solve the problem", attachments: context).contentForModel
    #expect(outgoing.contains("Explain time and space complexity."))
    let encoded = ChatAttachment.context(context).components(separatedBy: "\n").dropFirst().joined(separator: "\n")
    let payload = try JSONDecoder().decode([[String: String]].self, from: Data(encoded.utf8))
    #expect(payload.first?["filename"]?.contains(skill.file.path) == true)
}

@Test @MainActor func switchingACPAgentsSharesFreshProjectSkillsWithoutChangingTheTranscript() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("agent.py")
    try #"""
    import json, sys
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); result={}
        if method=='initialize': result={'protocolVersion':1}
        elif method=='session/new': result={'sessionId':'skills'}
        elif method=='session/prompt':
            text='\n'.join(b.get('text','') for b in m['params']['prompt'])
            markers=[v for v in ['GLOBAL_MARKER','DSA_V1','DSA_V2','OTHER_MARKER'] if v in text]
            reply=sys.argv[1]+':'+','.join(markers)
            print(json.dumps({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'skills','update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':reply}}}}),flush=True)
            result={'stopReason':'end_turn'}
        print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':result}),flush=True)
    """#.write(to: script, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
    let dsa = root.appendingPathComponent("DSA")
    let other = root.appendingPathComponent("Other")
    let global = try await store.skillFiles.create(name: "global", text: "GLOBAL_MARKER", project: nil)
    var scoped = try await store.skillFiles.create(name: "dsa", text: "DSA_V1", project: dsa)
    let unrelated = try await store.skillFiles.create(name: "other", text: "OTHER_MARKER", project: other)
    for skill in [global, scoped, unrelated] { try await store.saveSkill(skill) }
    store.installed = ["first", "second"].map { id in
        InstalledAgent(id: id, name: id, version: "1", executable: "/usr/bin/python3",
            arguments: ["-u", script.path, id], environment: [:], directory: root.path)
    }
    defer { store.resetChat() }
    for id in ["first", "second"] {
        store.resetChat()
        store.workspace = dsa
        store.selectedAgentID = id
        await store.connect()
        store.send("Question", useAgent: true)
        await store.sendTask?.value
        #expect(store.messages.last?.text == "\(id):GLOBAL_MARKER,DSA_V1")
        #expect(store.messages.first?.text == "Question" && store.messages.first?.attachments?.isEmpty != false)
    }
    try await store.skillFiles.save(scoped, text: "DSA_V2")
    store.send("Next question", useAgent: true)
    await store.sendTask?.value
    #expect(store.messages.last?.text == "second:GLOBAL_MARKER,DSA_V2")
    scoped.enabled = false
    try await store.saveSkill(scoped)
    store.send("Without project skill", useAgent: true)
    await store.sendTask?.value
    #expect(store.messages.last?.text == "second:GLOBAL_MARKER")
}

private func skillTestRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-skills-\(UUID())")
}

@Test @MainActor func bundledCavemanInstallsOfflineSharesContextAndPreservesTogglesAndEdits() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let state = root.appendingPathComponent("state.json")
    let store = AppStore(stateURL: state)
    try await store.installBundledSkill(.caveman)
    let skill = try #require(store.skills.first)
    #expect(skill.name == "caveman" && skill.project == nil && skill.enabled)
    #expect(skill.file.path.hasSuffix("Skills/Bundled/caveman/SKILL.md"))
    let source = try String(contentsOf: BundledSkill.caveman.resource("SKILL", extension: "md"), encoding: .utf8)
    #expect(try await store.skillFiles.read(skill) == source)
    #expect(source.contains("### 6. Payload verbatim"))
    for file in ["LICENSE", "LICENSE-MIT", "NOTICE", "SOURCE.txt"] {
        #expect(FileManager.default.fileExists(atPath: skill.file.deletingLastPathComponent().appendingPathComponent(file).path))
    }
    for project in [URL?.none, URL(fileURLWithPath: "/Example/Project")] {
        let context = try await store.skillFiles.context(store.skills, workspace: project)
        #expect(context.count == 1 && context[0].text.contains(source))
        let message = ChatMessage(role: "user", text: "Explain this code.", attachments: context)
        #expect(message.contentForModel.contains("Payload verbatim"))
        #expect(message.text == "Explain this code.")
    }
    var disabled = skill
    disabled.enabled = false
    try await store.saveSkill(disabled)
    let reopened = AppStore(stateURL: state)
    try await reopened.loadSkills()
    #expect(reopened.skills.first?.id == skill.id && reopened.skills.first?.enabled == false)
    #expect(try await reopened.skillFiles.context(reopened.skills, workspace: nil).isEmpty)
    try await reopened.skillFiles.save(disabled, text: "My custom concise response instructions.")
    try await reopened.removeSkill(disabled)
    try await reopened.installBundledSkill(.caveman)
    #expect(reopened.skills.count == 1)
    #expect(try await reopened.skillFiles.read(reopened.skills[0]) == "My custom concise response instructions.")
    try await reopened.installBundledSkill(.caveman)
    #expect(reopened.skills.count == 1)
}

@Test func skillDiscoveryFindsStandardFoldersNestedSkillsAndSymlinksWithoutScanningTheProject() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appendingPathComponent("Home")
    let project = root.appendingPathComponent("DSA")
    let global = root.appendingPathComponent("OneCapSkills")
    let files = SkillFiles(globalDirectory: global, homeDirectory: home)
    let paths = [".agents/skills", ".claude/skills", ".cursor/skills", ".codex/skills", ".onecap/skills",
        ".opencode/skills", ".github/skills", ".copilot/skills", ".kimi-code/skills"]
    for (index, path) in paths.enumerated() {
        for scope in [home, project] {
            let folder = scope.appendingPathComponent(path + "/group/skill-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: skill-\(index)\n---\nInstructions".write(
                to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
    }
    let native = try await files.create(name: "native", text: "Native instructions", project: nil)
    let ignored = project.appendingPathComponent("Unrelated")
    try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
    try "Not in a skill folder".write(to: ignored.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let agents = home.appendingPathComponent(".agents/skills")
    try FileManager.default.createSymbolicLink(at: agents.appendingPathComponent("cycle"), withDestinationURL: agents)
    try FileManager.default.createSymbolicLink(at: agents.appendingPathComponent("alias"), withDestinationURL: native.file.deletingLastPathComponent())
    let invalid = agents.appendingPathComponent("invalid")
    try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
    try Data([0, 255]).write(to: invalid.appendingPathComponent("SKILL.md"))
    let found = try await files.discover(projects: [project, project])
    // The same native file may be found through another root; the store deduplicates it.
    #expect(Set(found.map(\.file)).count == 19)
    #expect(Set(found.filter { $0.project != nil }.map(\.file)).count == 9)
    #expect(found.allSatisfy { $0.discovered == true && !$0.enabled })
    #expect(!found.contains { $0.file.path.contains("Unrelated") || $0.file.path.contains("invalid") })
}

@Test @MainActor func skillRescanPreservesTogglesAndIDsAndHandlesFilesBeingRemoved() async throws {
    let root = skillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let state = root.appendingPathComponent("state.json")
    let project = root.appendingPathComponent("DSA")
    let folder = project.appendingPathComponent(".agents/skills/context")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("SKILL.md")
    try "Project instructions".write(to: file, atomically: true, encoding: .utf8)
    let store = AppStore(stateURL: state)
    store.projectFolders = [project]
    try await store.discoverSkills()
    var skill = try #require(store.skills.first)
    #expect(!skill.enabled)
    #expect(skill.project?.path == project.path)
    skill.enabled = true
    try await store.saveSkill(skill)
    try await store.discoverSkills()
    #expect(store.skills.count == 1 && store.skills.first?.id == skill.id && store.skills.first?.enabled == true)
    #expect(try await store.skillFiles.context(store.skills, workspace: project).count == 1)
    try FileManager.default.removeItem(at: file)
    #expect(try await store.skillFiles.context(store.skills, workspace: project).isEmpty)
    try "Updated instructions".write(to: file, atomically: true, encoding: .utf8)
    let reopened = AppStore(stateURL: state)
    reopened.projectFolders = [project]
    try await reopened.discoverSkills()
    #expect(reopened.skills.first?.id == skill.id && reopened.skills.first?.enabled == true)
    let context = try await reopened.skillFiles.context(reopened.skills, workspace: project)
    #expect(context.first?.text.contains("Updated instructions") == true)
    #expect(try await reopened.skillFiles.context(reopened.skills, workspace: root.appendingPathComponent("Other")).isEmpty)
}
