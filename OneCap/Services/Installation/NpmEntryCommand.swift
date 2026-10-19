import Foundation

/// npm packages can expose either JavaScript launchers or native macOS executables.
enum NpmEntryCommand {
    static func make(entry: URL, staging: URL, destination: URL, node: URL, arguments: [String])
    throws -> AgentCommand
    {
        let handle = try FileHandle(forReadingFrom: entry)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        let machOHeaders: Set<Data> = [
            Data([0xcf, 0xfa, 0xed, 0xfe]), Data([0xce, 0xfa, 0xed, 0xfe]),
            Data([0xfe, 0xed, 0xfa, 0xcf]), Data([0xfe, 0xed, 0xfa, 0xce]),
            Data([0xca, 0xfe, 0xba, 0xbe]), Data([0xbe, 0xba, 0xfe, 0xca]),
            Data([0xca, 0xfe, 0xba, 0xbf]), Data([0xbf, 0xba, 0xfe, 0xca]),
        ]
        let base = staging.resolvingSymlinksInPath().path + "/"
        guard entry.path.hasPrefix(base) else {
            throw AppFailure("The npm executable is outside its installation.")
        }
        let relative = String(entry.path.dropFirst(base.count))
        let published = destination.appendingPathComponent(relative).path
        if machOHeaders.contains(header) {
            guard FileManager.default.isExecutableFile(atPath: entry.path) else {
                throw AppFailure("The bundled native executable does not have execute permission.")
            }
            return AgentCommand(executable: published, arguments: arguments, environment: [:])
        }
        return AgentCommand(executable: node.path, arguments: [published] + arguments, environment: [:])
    }
}
