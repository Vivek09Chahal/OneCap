import Foundation

/// Official ACP agents not yet included in the upstream registry.
enum SupplementalAgentCatalog {
    static let deepseek: Agent = {
        // Pin the published CLI, rather than following the rapidly changing preview branch.
        let version = "0.2.1-rc.5"
        return Agent(
            id: "deepseek-harness", name: "DeepSeek Harness", version: version,
            description: "Experimental · DeepSeek’s plugin-based coding agent. Developer preview; compatibility may change.",
            repository: "https://github.com/deepseek-ai/deepseek-harness",
            website: "https://deepseek-harness.github.io/deepseek-harness/", license: "MIT",
            distribution: .init(binary: nil, npx: .init(
                package: "@deepseek-ai/dsh@\(version)", args: ["--profile", "acp"], env: nil), uvx: nil))
    }()

    static let mimo: Agent = {
        let version = "0.1.16"
        let platforms = [
            "darwin-aarch64": ("arm64", "191d5c9634e8e24fe3038b31ea1191bdd8f23afcf5f389988cc6856077a632b3"),
            "darwin-x86_64": ("x64", "2cb812cc978379be322340fd59f22c6baa42f2bd2534078fb1d291a71220368f"),
        ]
        // Archives used by https://mimo.xiaomi.com/install, pinned after download verification.
        let binaries = platforms.mapValues { architecture, checksum in
            BinaryDistribution(
                archive: "https://mimocode.cnbj1.mi-fds.com/mimocode/mimocode/releases/v\(version)/mimocode-darwin-\(architecture).zip",
                cmd: "./mimo", args: ["acp"], env: nil, sha256: checksum)
        }
        return Agent(
            id: "mimocode", name: "MiMo Code", version: version,
            description: "Xiaomi’s MiMo coding agent", repository: nil,
            website: "https://mimo.xiaomi.com/coder/docs", license: nil,
            distribution: .init(binary: binaries, npx: nil, uvx: nil))
    }()
}
