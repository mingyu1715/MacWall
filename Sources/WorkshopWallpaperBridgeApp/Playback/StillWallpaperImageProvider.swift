import AppKit
import AVFoundation
import WorkshopWallpaperCore

struct StillWallpaperImageProvider {
    let cacheDirectory: URL

    init(cacheDirectory: URL = Self.defaultCacheDirectory()) {
        self.cacheDirectory = cacheDirectory
    }

    func stillImageURL(for asset: WallpaperAsset) throws -> URL {
        if asset.kind == .video {
            guard let entrypoint = playableVideoURL(for: asset.entrypoint) else {
                throw SystemWallpaperError.conversionRequiredForStillImage
            }
            return try exportVideoFrame(from: entrypoint, assetId: asset.id)
        }
        if asset.kind == .image, let entrypoint = stillImageURL(for: asset.entrypoint) {
            return try normalizeStillImage(entrypoint, assetId: asset.id)
        }
        if let thumbnail = stillImageURL(for: asset.thumbnail) {
            return try normalizeStillImage(thumbnail, assetId: asset.id)
        }
        throw SystemWallpaperError.noStillImage
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "WorkshopWallpaperBridge")
            .appending(path: "GeneratedStillWallpapers")
    }

    private func playableVideoURL(for path: String?) -> URL? {
        guard let path else {
            return nil
        }
        let url = URL(filePath: path)
        guard playableVideoExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }
        return url
    }

    private func stillImageURL(for path: String?) -> URL? {
        guard let path else {
            return nil
        }
        let url = URL(filePath: path)
        guard stillImageExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }
        return url
    }

    private func exportVideoFrame(from videoURL: URL, assetId: String) throws -> URL {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        let output = cacheURL(assetId: assetId)
        let image: CGImage
        do {
            image = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
        } catch {
            image = try generator.copyCGImage(at: .zero, actualTime: nil)
        }
        try writePNG(NSBitmapImageRep(cgImage: image), to: output)
        return output
    }

    private func normalizeStillImage(_ url: URL, assetId: String) throws -> URL {
        let output = cacheURL(assetId: assetId)
        let data = try LockScreenWallpaperCache().pngData(from: url)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: output, options: [.atomic])
        return output
    }

    private func writePNG(_ representation: NSBitmapImageRep, to output: URL) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SystemWallpaperError.noStillImage
        }
        try data.write(to: output, options: [.atomic])
    }

    private func cacheURL(assetId: String) -> URL {
        cacheDirectory.appending(path: "\(safeFileName(assetId))-still.png")
    }

    private func safeFileName(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private let playableVideoExtensions = ["mp4", "mov", "m4v"]
private let stillImageExtensions = ["jpg", "jpeg", "png", "gif", "heic"]
