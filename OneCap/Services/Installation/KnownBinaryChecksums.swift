import Foundation

/// Pins for official archives whose registry entries omit a checksum. New releases
/// require new pins; a missing hash never silently disables download verification.
enum KnownBinaryChecksums {
    static func sha256(for archive: String) -> String? {
        switch archive {
        case "https://downloads.cursor.com/lab/2026.10.16-e3cb207/darwin/arm64/agent-cli-package.tar.gz":
            "5f04d196a84ddb5c20a4a466bdd74e3695bfb447e3c4a1e6071364b2b9497dd0"
        case "https://downloads.cursor.com/lab/2026.10.16-e3cb207/darwin/x64/agent-cli-package.tar.gz":
            "93372e384e9397b54b1e4fdb1812662f68e7b61c0c60cb3f2f4b788c9e0779c4"
        default: nil
        }
    }
}

extension BinaryDistribution {
    var verifiedSHA256: String? { sha256 ?? KnownBinaryChecksums.sha256(for: archive) }
}
