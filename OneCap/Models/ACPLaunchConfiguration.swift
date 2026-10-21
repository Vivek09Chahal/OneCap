import Foundation

extension InstalledAgent {
    /// Restore installations whose launch record was changed by the removed native route.
    /// Fresh installs already use the ACP distribution from the registry.
    func acpLaunch() throws -> InstalledAgent {
        guard ["codex-acp", "codex"].contains(id), arguments.contains("app-server") else { return self }
        let message = "Reinstall Codex from Agent Harnesses to restore its ACP connection."
        let root = URL(fileURLWithPath: directory)
        let package = try PackageValidation.containedPath("node_modules/@agentclientprotocol/codex-acp", in: root)
        let manifestURL = package.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw AppFailure(message) }
        struct Manifest: Decodable {
            let name: String
            let version: String
            let bin: NpmExecutable
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.name == "@agentclientprotocol/codex-acp", let entry = manifest.bin.entry else {
            throw AppFailure(message)
        }
        let binary = try PackageValidation.resolvedExecutable(entry, in: package, containedIn: root)
        let command = try NpmEntryCommand.make(entry: binary, staging: root, destination: root,
                                               node: URL(fileURLWithPath: executable), arguments: [])
        return InstalledAgent(id: id, name: name, version: manifest.version, executable: command.executable,
                              arguments: command.arguments, environment: environment, directory: directory)
    }
}
