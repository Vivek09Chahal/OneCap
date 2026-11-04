import Foundation

/// Official ACP agents not yet included in the upstream registry.
enum SupplementalAgentCatalog {
    static let mimo: Agent = {
        let version = "0.1.16"
        let platforms = [
            "darwin-aarch64": ("arm64", "ARM64_CHECKSUM"),
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
