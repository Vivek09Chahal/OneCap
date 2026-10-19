import Foundation

struct BinaryAgentInstaller: AgentDistributionInstalling {
    let binary: BinaryDistribution
    let downloader: any Downloading
    private let archive: any ArchiveExtracting

    init(binary: BinaryDistribution, downloader: any Downloading,
         archive: any ArchiveExtracting = ArchiveExtractor()) {
        self.binary = binary
        self.downloader = downloader
        self.archive = archive
    }
    
    func install(staging: URL, destination: URL) async throws
    -> AgentCommand
    {
        guard let url = URL(string: binary.archive), url.scheme == "https" else {
            throw AppFailure("The binary must use an HTTPS download URL.")
        }
        // Use the registry checksum or a reviewed pin for the exact official archive.
        guard let hash = binary.verifiedSHA256 else {
            throw AppFailure("This binary has no registry checksum. Installation is not supported yet.")
        }
        let data = try await downloader.data(url)
        try PackageValidation.verify(data, sha256: hash)
        try await archive.unpack(data, source: url, to: staging, rawCommand: binary.cmd)
        let command = try PackageValidation.containedPath(binary.cmd, in: staging)
        guard FileManager.default.fileExists(atPath: command.path) else {
            throw AppFailure("The agent executable is missing from its archive.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        let executable = destination.appendingPathComponent(binary.cmd).standardizedFileURL.path
        return AgentCommand(
            executable: executable, arguments: binary.args ?? [], environment: binary.env ?? [:])
    }
}
