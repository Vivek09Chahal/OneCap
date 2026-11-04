import Foundation

struct GitFile: Identifiable, Sendable {
    let path: String
    let originalPath: String?
    let index: Character
    let worktree: Character
    var id: String { path }
    var conflicted: Bool { index == "U" || worktree == "U" || (index == "A" && worktree == "A") || (index == "D" && worktree == "D") }
    var staged: Bool { index != " " && index != "?" && !conflicted }
    var unstaged: Bool { worktree != " " }
    var paths: [String] { [originalPath, path].compactMap { $0 } }
}

struct GitSnapshot: Sendable {
    let root: URL
    let branch: String
    let branches: [String]
    let remotes: [String]
    let files: [GitFile]
    let history: String
    let merging: Bool
}

/// Arguments go directly to Git, never through a shell. All changes use repository scope.
struct WorkspaceGit: Sendable {
    let folder: URL

    func run(_ arguments: [String]) async throws -> String {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["GIT_LITERAL_PATHSPECS"] = "1"
        return try await ProcessRunner(failureContext: "Git operation failed").run(
            "/usr/bin/git", ["-C", folder.path] + arguments, environment: environment)
    }

    func snapshot() async throws -> GitSnapshot {
        let root = try await run(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .newlines)
        let repository = WorkspaceGit(folder: URL(fileURLWithPath: root, isDirectory: true))
        let branch = try await repository.run(["status", "--short", "--branch"]).split(separator: "\n").first.map(String.init) ?? ""
        let branches = try await repository.run(["for-each-ref", "--format=%(refname:short)", "refs/heads/"])
        let remotes = try await repository.run(["remote"])
        let status = try await repository.run(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        // An unborn repository has no history yet.
        let hasHead = (try? await repository.run(["rev-parse", "--verify", "HEAD"])) != nil
        let history = hasHead ? try await repository.run(["log", "-20", "--format=%h  %s%n    %an · %ar"]) : "No commits yet."
        let mergePath = try await repository.run(["rev-parse", "--git-path", "MERGE_HEAD"]).trimmingCharacters(in: .newlines)
        let mergeURL = mergePath.hasPrefix("/") ? URL(fileURLWithPath: mergePath) : repository.folder.appendingPathComponent(mergePath)
        return GitSnapshot(root: repository.folder, branch: branch, branches: branches.split(separator: "\n").map(String.init),
                           remotes: remotes.split(separator: "\n").map(String.init), files: Self.parseStatus(status),
                           history: history, merging: FileManager.default.fileExists(atPath: mergeURL.path))
    }

    static func parseStatus(_ output: String) -> [GitFile] {
        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        var files: [GitFile] = []
        var offset = 0
        while offset < records.count {
            let record = Array(records[offset])
            offset += 1
            guard record.count >= 4 else { continue }
            let renamed = record[0] == "R" || record[0] == "C" || record[1] == "R" || record[1] == "C"
            let original = renamed && offset < records.count ? String(records[offset]) : nil
            if original != nil { offset += 1 }
            files.append(GitFile(path: String(record.dropFirst(3)), originalPath: original, index: record[0], worktree: record[1]))
        }
        return files
    }

    func stage(_ file: GitFile? = nil) async throws {
        _ = try await run(["add", "--all", "--"] + (file?.paths ?? ["."]))
    }

    func unstage(_ file: GitFile? = nil) async throws {
        let hasHead = (try? await run(["rev-parse", "--verify", "HEAD"])) != nil
        let command = hasHead ? ["reset", "--quiet", "HEAD", "--"] : ["rm", "--cached", "-r", "--"]
        _ = try await run(command + (file?.paths ?? ["."]))
    }

    func commit(subject: String, description: String) async throws {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw AppFailure("Enter a commit message.") }
        var arguments = ["commit", "-m", subject]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { arguments += ["-m", description] }
        _ = try await run(arguments)
    }

    func createBranch(_ name: String) async throws {
        _ = try await run(["check-ref-format", "--branch", name])
        _ = try await run(["switch", "-c", name])
    }
}
