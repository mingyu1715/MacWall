import Foundation

struct MacWallNativeWallpaperVideoSource {
    static let bundledProbeResourceName = "macwall-native-wallpaper-sample"
    static let bundledProbeResourceExtension = "mp4"

    let url: URL

    static func bundledProbeURL(bundle: Bundle = .main) -> URL? {
        guard let resourceURL = bundle.url(
            forResource: bundledProbeResourceName,
            withExtension: bundledProbeResourceExtension
        ) else {
            return nil
        }

        return firstExistingURL(candidates: [resourceURL])
    }

    static func firstExistingURL(
        candidates: [URL],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        candidates.first { url in
            url.isFileURL && fileExists(url.path)
        }
    }
}
