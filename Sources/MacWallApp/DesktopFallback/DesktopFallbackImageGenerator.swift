import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MacWallCore

struct DesktopFallbackImageGenerator: Sendable {
    typealias ExportVideoFrame = @Sendable (URL, Double, URL) throws -> Void
    typealias NormalizeImage = @Sendable (URL, URL) throws -> Void

    private let exportVideoFrame: ExportVideoFrame
    private let normalizeImage: NormalizeImage

    init(
        exportVideoFrame: @escaping ExportVideoFrame = Self.exportVideoFrame,
        normalizeImage: @escaping NormalizeImage = Self.normalizeImage
    ) {
        self.exportVideoFrame = exportVideoFrame
        self.normalizeImage = normalizeImage
    }

    func generate(asset: WallpaperAsset, output: URL) async throws {
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            switch asset.kind {
            case .video:
                guard let input = Self.playableVideoURL(asset.entrypoint) else {
                    throw DesktopFallbackError.unsupportedAsset
                }
                try exportVideoFrame(input, 0.5, output)
            case .image:
                guard let input = Self.imageURL(asset.entrypoint) else {
                    throw DesktopFallbackError.unsupportedAsset
                }
                try normalizeImage(input, output)
            case .web, .scene, .unknown:
                throw DesktopFallbackError.unsupportedAsset
            }
        }.value
    }

    private static func playableVideoURL(_ path: String?) -> URL? {
        guard let path else {
            return nil
        }
        let url = URL(filePath: path)
        return playableVideoExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }

    private static func imageURL(_ path: String?) -> URL? {
        guard let path else {
            return nil
        }
        let url = URL(filePath: path)
        return imageExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }

    private static func exportVideoFrame(input: URL, seconds: Double, output: URL) throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
        generator.appliesPreferredTrackTransform = true
        let image: CGImage
        do {
            image = try generator.copyCGImage(
                at: CMTime(seconds: seconds, preferredTimescale: 600),
                actualTime: nil
            )
        } catch {
            image = try generator.copyCGImage(at: .zero, actualTime: nil)
        }
        try writePNG(image, to: output)
    }

    private static func normalizeImage(input: URL, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DesktopFallbackError.invalidImage
        }
        try writePNG(image, to: output)
    }

    private static func writePNG(_ image: CGImage, to output: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DesktopFallbackError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesktopFallbackError.invalidImage
        }
    }
}

enum DesktopFallbackError: Error, Equatable, LocalizedError {
    case unsupportedAsset
    case invalidImage
    case webPolicyUnavailable
    case webNavigationFailed
    case webSnapshotFailed
    case liveSnapshotUnavailable
    case timedOut
    case generationInvalidated

    var errorDescription: String? {
        switch self {
        case .unsupportedAsset:
            return "This item cannot generate a desktop fallback."
        case .invalidImage:
            return "The desktop fallback image could not be generated."
        case .webPolicyUnavailable:
            return "The local-only Web wallpaper policy could not be installed."
        case .webNavigationFailed:
            return "The local Web wallpaper could not be loaded."
        case .webSnapshotFailed:
            return "The Web wallpaper snapshot could not be generated."
        case .liveSnapshotUnavailable:
            return "The live wallpaper could not provide a desktop fallback snapshot."
        case .timedOut:
            return "Desktop fallback generation timed out."
        case .generationInvalidated:
            return "Desktop fallback generation was replaced by a newer request."
        }
    }
}

private let playableVideoExtensions = ["mp4", "mov", "m4v"]
private let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic"]
