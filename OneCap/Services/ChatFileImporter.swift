import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

actor ChatFileImporter {
    static let maximumFiles = 5
    static let maximumBytes = 256 * 1024
    static let maximumPDFBytes = 10 * 1024 * 1024
    static let maximumImageBytes = 10 * 1024 * 1024
    
    func read(_ urls: [URL], relativeTo folder: URL? = nil) throws -> [ChatAttachment] {
        guard urls.count <= Self.maximumFiles else {
            throw AppFailure("Attach up to five files per message.")
        }
        return try urls.map { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw AppFailure("Choose a regular image, PDF, text, or code file.")
            }
            let root = folder?.resolvingSymlinksInPath().standardizedFileURL.path
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard root.map({ path.hasPrefix($0 + "/") }) ?? true else {
                throw AppFailure("The selected file is no longer inside this project folder.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumImageBytes + 1) ?? Data()
            let name = root.flatMap { path.hasPrefix($0 + "/") ? String(path.dropFirst($0.count + 1)) : nil }
                ?? url.lastPathComponent
            if url.pathExtension.lowercased() == "pdf" || data.starts(with: Data("%PDF-".utf8)) {
                guard data.count <= Self.maximumPDFBytes else { throw AppFailure("PDFs must be 10 MB or smaller.") }
                guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
                    throw AppFailure("\(url.lastPathComponent) is locked or could not be read as a PDF.")
                }
                let text = document.string ?? ""
                guard text.utf8.count <= Self.maximumBytes else {
                    throw AppFailure("\(url.lastPathComponent) exceeds the 256 KB extracted text limit.")
                }
                return ChatAttachment(name: name,
                    text: text.isEmpty ? "This PDF has no extractable text." : text,
                    mimeType: "application/pdf", pdfData: data)
            }
            if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
                return try image(data, name: name)
            }
            guard data.count <= Self.maximumBytes else {
                throw AppFailure("\(url.lastPathComponent) exceeds the 256 KB attachment limit.")
            }
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                throw AppFailure(
                    "\(url.lastPathComponent) is not a UTF-8 text file. Attach a text or code file instead.")
            }
            return ChatAttachment(name: name, text: text)
        }
    }

    func image(_ data: Data, name: String) throws -> ChatAttachment {
        guard data.count <= Self.maximumImageBytes else { throw AppFailure("Images must be 10 MB or smaller.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw AppFailure("This image could not be read.")
        }
        guard image.width * image.height <= 40_000_000 else { throw AppFailure("Choose an image smaller than 40 megapixels.") }
        let identifier = type as String
        let mime = [UTType.png.identifier: "image/png", UTType.jpeg.identifier: "image/jpeg",
                    UTType.gif.identifier: "image/gif", UTType.webP.identifier: "image/webp"][identifier]
        if let mime { return ChatAttachment(name: name, text: "", imageData: data, mimeType: mime) }
        let converted = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(converted, UTType.png.identifier as CFString, 1, nil) else {
            throw AppFailure("This image format could not be converted to PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), converted.length <= Self.maximumImageBytes else {
            throw AppFailure("The converted image exceeds the 10 MB limit.")
        }
        return ChatAttachment(name: (name as NSString).deletingPathExtension + ".png", text: "",
            imageData: converted as Data, mimeType: "image/png")
    }
}
