import Foundation
import Testing
@testable import OneCapCore

private func gitFixture() async throws -> WorkspaceGit {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OneCap-Git-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let git = WorkspaceGit(folder: folder)
    _ = try await git.run(["init", "-b", "main"])
    for arguments in [["user.name", "OneCap Tests"], ["user.email", "tests@example.invalid"],
                      ["commit.gpgsign", "false"], ["core.hooksPath", "/dev/null"]] {
        _ = try await git.run(["config"] + arguments)
    }
    return git
}

@Test func gitStatusPreservesUnusualPathsAndRenameSources() {
    let files = WorkspaceGit.parseStatus("?? line\nbreak.txt\0R  renamed file\0original file\0UU conflict\0 M :[abc]\0")
    #expect(files.count == 4)
    #expect(files[0].path == "line\nbreak.txt")
    #expect(!files[0].staged && files[0].unstaged)
    #expect(files[1].paths == ["original file", "renamed file"])
    #expect(files[1].staged && !files[1].unstaged)
    #expect(files[2].conflicted)
    #expect(files[3].path == ":[abc]")
}

@Test func gitStagesOnlySelectedFilesAndCommitsSubjectAndDescription() async throws {
    let git = try await gitFixture()
    defer { try? FileManager.default.removeItem(at: git.folder) }
    for name in ["selected file", "keep untracked", ":[literal]"] {
        try "hello".write(to: git.folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    var snapshot = try await git.snapshot()
    #expect(snapshot.files.count == 3)
    let selected = try #require(snapshot.files.first { $0.path == "selected file" })
    try await git.stage(selected)
    try await git.unstage(selected) // Also works before the initial commit.
    #expect(try await git.snapshot().files.allSatisfy { !$0.staged })
    try await git.stage(selected)
    try await git.commit(subject: "First commit", description: "Longer description\nwith details.")
    let body = try await git.run(["log", "-1", "--format=%B"])
    #expect(body == "First commit\n\nLonger description\nwith details.\n\n")
    snapshot = try await git.snapshot()
    #expect(snapshot.files.count == 2)
    let literal = try #require(snapshot.files.first { $0.path == ":[literal]" })
    try await git.stage(literal)
    #expect(try await git.snapshot().files.first { $0.path == ":[literal]" }?.staged == true)
    try await git.unstage()
    #expect(try await git.snapshot().files.allSatisfy { !$0.staged })
}

@Test func gitCreatesSwitchesAndMergesBranchesAndReportsErrors() async throws {
    let git = try await gitFixture()
    defer { try? FileManager.default.removeItem(at: git.folder) }
    let file = git.folder.appendingPathComponent("file.txt")
    try "base\n".write(to: file, atomically: true, encoding: .utf8)
    try await git.stage()
    try await git.commit(subject: "Base", description: "")
    try await git.createBranch("feature/test")
    try "feature\n".write(to: file, atomically: true, encoding: .utf8)
    try await git.stage()
    try await git.commit(subject: "Feature", description: "")
    _ = try await git.run(["switch", "main"])
    _ = try await git.run(["merge", "--no-edit", "feature/test"])
    #expect(try String(contentsOf: file, encoding: .utf8) == "feature\n")
    #expect(try await git.snapshot().branches.contains("feature/test"))
    do {
        try await git.createBranch("feature/test")
        Issue.record("Duplicate branch should fail")
    } catch {
        #expect(error.localizedDescription.contains("already exists"))
    }
}

@Test func gitPushAndFastForwardPullUseLocalRemote() async throws {
    let git = try await gitFixture()
    let remote = git.folder.appendingPathComponent("remote.git")
    let clone = git.folder.appendingPathComponent("clone")
    defer { try? FileManager.default.removeItem(at: git.folder) }
    _ = try await git.run(["init", "--bare", remote.path])
    _ = try await git.run(["commit", "--allow-empty", "-m", "Base"])
    _ = try await git.run(["remote", "add", "origin", remote.path])
    _ = try await git.run(["push", "--set-upstream", "origin", "HEAD"])
    _ = try await git.run(["clone", "--branch", "main", remote.path, clone.path])
    _ = try await git.run(["commit", "--allow-empty", "-m", "Next"])
    _ = try await git.run(["push", "--set-upstream", "origin", "HEAD"])
    let other = WorkspaceGit(folder: clone)
    _ = try await other.run(["fetch", "origin"])
    _ = try await other.run(["pull", "--ff-only", "origin"])
    let head = try await git.run(["rev-parse", "HEAD"])
    #expect(try await other.run(["rev-parse", "HEAD"]) == head)
}
