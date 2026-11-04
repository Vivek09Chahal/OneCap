import DLS
import SwiftUI

struct WorkspaceGitView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folder: URL
    @State private var snapshot: GitSnapshot?
    @State private var busy = false
    @State private var notice = ""
    @State private var subject = ""
    @State private var commitDescription = ""
    @State private var branchName = ""
    @State private var targetBranch = ""
    @State private var remote = ""
    @State private var mergeConfirmation = false

    private var repository: WorkspaceGit { WorkspaceGit(folder: snapshot?.root ?? folder) }
    private var blocked: Bool { busy || store.sending || store.applyingFileUndo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Source Control").font(.title2.bold())
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Refresh") { perform { } }.disabled(blocked)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
            if let snapshot {
                Text(snapshot.root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(snapshot.branch).font(.headline)
                Text("Actions apply to the entire repository, including files outside the selected folder.")
                    .font(.caption).foregroundStyle(.secondary)
                controls(snapshot)
                    .disabled(blocked)
                Divider()
                HSplitView {
                    changes(snapshot).frame(minWidth: 330)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Commit staged changes").font(.headline)
                        TextField("Commit message", text: $subject)
                        Text("Description (optional)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $commitDescription).frame(height: 100).border(.quaternary)
                        Button(snapshot.merging ? "Commit merge" : "Commit") {
                            perform {
                                try await repository.commit(subject: subject, description: commitDescription)
                                subject = ""
                                commitDescription = ""
                            }
                        }
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || (!snapshot.files.contains(where: \.staged) && !snapshot.merging)
                                  || snapshot.files.contains(where: \.conflicted))
                        Divider()
                        Text("Recent commits").font(.headline)
                        ScrollView {
                            Text(snapshot.history).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 16).frame(minWidth: 280)
                    .disabled(blocked)
                }
            } else if !busy {
                ContentUnavailableView("Git repository unavailable", systemImage: "arrow.triangle.branch",
                                       description: Text("Choose a folder containing an existing Git repository."))
            }
            if !notice.isEmpty {
                ScrollView { Text(notice).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 85)
            }
        }
        .padding(24).frame(width: 820, height: 680)
        .interactiveDismissDisabled(busy)
        .task { perform { } }
        .confirmationDialog("Merge \(targetBranch) into the current branch?", isPresented: $mergeConfirmation) {
            Button("Merge branch") { perform { _ = try await repository.run(["merge", "--no-edit", targetBranch]) } }
        } message: {
            Text("This can create a merge commit. If conflicts occur, edit the conflicted files, stage them, and commit the merge here.")
        }
    }

    private func controls(_ snapshot: GitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Branch", selection: $targetBranch) {
                    Text("Choose branch").tag("")
                    ForEach(snapshot.branches, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 320)
                Button("Switch") { perform { _ = try await repository.run(["switch", targetBranch]) } }
                    .disabled(targetBranch.isEmpty || snapshot.merging)
                Button("Merge…") { mergeConfirmation = true }
                    .disabled(targetBranch.isEmpty || snapshot.merging)
                if snapshot.merging { Text("Merge in progress").foregroundStyle(.orange) }
            }
            HStack {
                TextField("New branch name", text: $branchName).frame(maxWidth: 320)
                Button("Create & switch") {
                    perform { try await repository.createBranch(branchName); branchName = "" }
                }.disabled(branchName.isEmpty || snapshot.merging)
            }
            HStack {
                Picker("Remote", selection: $remote) {
                    Text("Choose remote").tag("")
                    ForEach(snapshot.remotes, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 320)
                Button("Fetch") { perform { _ = try await repository.run(["fetch", remote]) } }
                Button("Pull") { perform { _ = try await repository.run(["pull", "--ff-only", remote]) } }
                    .help("Fast-forward only; uses the current branch’s configured upstream")
                    .disabled(snapshot.merging)
                Button("Push") { perform { _ = try await repository.run(["push", "--set-upstream", remote, "HEAD"]) } }
                    .help("Push the current branch and configure its upstream")
            }.disabled(remote.isEmpty)
            Text("Remote actions use your existing Git credentials. Configure authentication outside OneCap if Git requests sign-in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func changes(_ snapshot: GitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changes (\(snapshot.files.count))").font(.headline)
                Spacer()
                Button("Stage all") { perform { try await repository.stage() } }
                Button("Unstage all") { perform { try await repository.unstage() } }
            }.disabled(blocked || snapshot.files.isEmpty)
            List(snapshot.files) { file in
                VStack(alignment: .leading, spacing: 6) {
                    Text(file.path).lineLimit(2).textSelection(.enabled).help(file.path)
                    HStack {
                        Text(file.conflicted ? "Conflict" : "\(file.index)\(file.worktree)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if file.unstaged {
                            Button(file.conflicted ? "Stage resolution" : "Stage") {
                                perform { try await repository.stage(file) }
                            }
                        }
                        if file.staged {
                            Button("Unstage") { perform { try await repository.unstage(file) } }
                        }
                    }.font(.caption)
                }.padding(.vertical, 4)
            }.disabled(blocked)
            Text("Left status: staged · Right status: working copy · ?? untracked")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.trailing, 16)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !blocked else { return }
        busy = true
        store.applyingFileUndo = true
        notice = ""
        Task { @MainActor in
            defer {
                busy = false
                store.applyingFileUndo = false
                store.fileTreeRevision = UUID()
            }
            do { try await action(); notice = "Git status refreshed." }
            catch { notice = error.localizedDescription }
            do {
                snapshot = try await repository.snapshot()
                if remote.isEmpty { remote = snapshot?.remotes.first(where: { $0 == "origin" }) ?? snapshot?.remotes.first ?? "" }
            } catch { notice += "\n" + error.localizedDescription }
        }
    }
}
