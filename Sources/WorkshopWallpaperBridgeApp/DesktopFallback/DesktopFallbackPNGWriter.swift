import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DesktopFallbackPNGWriter {
    static func write(_ image: NSImage, to output: URL) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DesktopFallbackError.webSnapshotFailed
        }
        try write(cgImage, to: output)
    }

    static func write(_ image: CGImage, to output: URL) throws {
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DesktopFallbackError.webSnapshotFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesktopFallbackError.webSnapshotFailed
        }
    }
}
