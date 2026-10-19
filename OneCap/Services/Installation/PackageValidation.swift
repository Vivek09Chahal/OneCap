import CryptoKit
import Foundation

enum PackageValidation {
    static func safeComponent(_ text: String) throws -> String {
        guard !text.isEmpty, text != ".", text != "..",
              text.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.@")).contains($0)
              })
                else {
            throw AppFailure("The registry contains an invalid identifier or version.")
        }
        return text
    }
    static func containedPath(_ path: String, in root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw AppFailure("The package contains an unsafe path.")
        }
        let result = root.appendingPathComponent(path).standardizedFileURL
        var prefix = root
        for component in path.split(separator: "/") where component != "." {
            prefix.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: prefix.path)) != nil {
                throw AppFailure("Executable paths must not pass through symbolic links.")
            }
        }
        let resolved = result.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw AppFailure("The package points outside its installation folder.")
        }
        return result
    }
    /// npm postinstall scripts may link their entry to a bundled executable. Keep the
    /// resolved entry inside this installation; managed removal paths remain link-free.
    static func resolvedExecutable(_ path: String, in package: URL, containedIn installation: URL)
    throws -> URL
    {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw AppFailure("The package contains an unsafe executable path.")
        }
        let boundary = installation.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var entry = package.resolvingSymlinksInPath().standardizedFileURL
        guard entry.path.hasPrefix(boundary) else {
            throw AppFailure("The package points outside its installation folder.")
        }
        for component in path.split(separator: "/") where component != "." {
            entry.appendPathComponent(String(component))
            // Check each hop, including links to directories, before following the next component.
            var seen: Set<String> = []
            while let target = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path) {
                guard seen.insert(entry.path).inserted else {
                    throw AppFailure("The package executable contains a symbolic link cycle.")
                }
                entry =
                (target.hasPrefix("/")
                 ? URL(fileURLWithPath: target)
                 : entry.deletingLastPathComponent().appendingPathComponent(target)).standardizedFileURL
                guard entry.path.hasPrefix(boundary) else {
                    throw AppFailure("The package executable links outside its installation folder.")
                }
            }
            entry = entry.resolvingSymlinksInPath().standardizedFileURL
            guard entry.path.hasPrefix(boundary) else {
                throw AppFailure("The package executable links outside its installation folder.")
            }
        }
        guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw AppFailure("The npm entry point is missing or is not a regular file.")
        }
        return entry
    }
    
    static func verify(_ data: Data, sha256: String) throws {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == sha256.lowercased() else {
            throw AppFailure("Download checksum mismatch. Installation stopped.")
        }
    }
}
