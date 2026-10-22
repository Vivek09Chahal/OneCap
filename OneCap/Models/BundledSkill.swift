import Foundation

enum BundledSkill: String, Identifiable, Sendable {
    case caveman

    var id: String { rawValue }
    var title: String { "Caveman" }
    var summary: String { "Shorter answers with technical details preserved. Code, commands, and paths stay exact." }
    var website: URL { URL(string: "https://github.com/juliusbrussee/caveman#say-less-the-caveman-voice")! }

    func resource(_ name: String, extension fileExtension: String) throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "Caveman-" + name, withExtension: fileExtension) else {
            throw AppFailure("The bundled Caveman skill is missing. Reinstall OneCap to restore it.")
        }
        return url
    }
}
