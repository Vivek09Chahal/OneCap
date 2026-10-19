import AppKit
import SwiftUI

/// Compile with MazeMark.swift and the DLS ColorTokens.swift source, then run from the repository root.
@main struct GenerateAppIcon {
  @MainActor static func main() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("OneCap/Assets.xcassets/AppIcon.appiconset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let artwork = ZStack {
      RoundedRectangle(cornerRadius: 190, style: .continuous)
        .fill(
          LinearGradient(
            colors: [DLSColors.light.surface, DLSColors.light.accentSubtle],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 190, style: .continuous)
            .strokeBorder(DLSColors.light.borderStrong.opacity(0.5), lineWidth: 2)
        )
        .padding(52)
        .shadow(color: DLSColors.light.textPrimary.opacity(0.18), radius: 18, y: 12)
      MazeMark()
        .stroke(
          DLSColors.light.accent,
          style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 660, height: 660)
    }.frame(width: 1024, height: 1024)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
      for scale in [1, 2] {
        let pixels = points * scale
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = CGFloat(pixels) / 1024
        guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
          throw CocoaError(.fileWriteUnknown)
        }
        let filename = "maze-\(points)@\(scale)x.png"
        try data.write(to: directory.appendingPathComponent(filename))
        images.append([
          "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename,
        ])
      }
    }
    let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("Contents.json"))
  }
}
