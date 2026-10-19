import Foundation

struct NpmAgentInstaller: AgentDistributionInstalling {
    let npm: PackageDistribution
    let root: URL
    let runtime: any NodeRuntimeProviding
    private let runner: any ProcessRunning

    init(npm: PackageDistribution, root: URL, runtime: any NodeRuntimeProviding,
         runner: any ProcessRunning = ProcessRunner()) {
        self.npm = npm
        self.root = root
        self.runtime = runtime
        self.runner = runner
    }
    
    func install(staging: URL, destination: URL) async throws
    -> AgentCommand
    {
        let node = try await runtime.binary()
        let npmCLI = node.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/node_modules/npm/bin/npm-cli.js")
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = node.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["npm_config_cache"] = root.appendingPathComponent("npm-cache").path
        guard !npm.package.hasPrefix("-"), !npm.package.contains("://"), !npm.package.contains("..")
                else { throw AppFailure("Unsupported npm package specifier.") }
        _ = try await runner.run(
            node.path,
            [
                npmCLI.path, "install", "--prefix", staging.path, "--save-exact", "--no-audit", "--no-fund",
                "--", npm.package,
            ], environment: env)
        let name = Self.packageName(npm.package)
        let packageRoot = try PackageValidation.containedPath("node_modules/\(name)", in: staging)
        let manifest = try JSONDecoder().decode(
            NpmManifest.self, from: Data(contentsOf: packageRoot.appendingPathComponent("package.json")))
        guard let entry = manifest.bin.entry else {
            throw AppFailure("The npm package has no executable.")
        }
        let entryURL = try PackageValidation.resolvedExecutable(
            entry, in: packageRoot, containedIn: staging)
        let command = try NpmEntryCommand.make(
            entry: entryURL, staging: staging,
            destination: destination, node: node, arguments: npm.args ?? [])
        var environment = npm.env ?? [:]
        environment["PATH"] = env["PATH"]
        return AgentCommand(
            executable: command.executable, arguments: command.arguments, environment: environment)
    }
    static func packageName(_ spec: String) -> String {
        guard let separator = spec.dropFirst().lastIndex(of: "@") else { return spec }
        return String(spec[..<separator])
    }
}
