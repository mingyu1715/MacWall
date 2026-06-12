import CoreGraphics
import Foundation
import ImageIO
import ObjectiveC
import UniformTypeIdentifiers

private let spikeChoiceIdentifier = "macwall-native-spike-choice"

func makeSpikeSettingsViewModelsXPC() -> AnyObject? {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.mingyu1715.macwall.native-wallpaper-spike.extension"
    guard let thumbnailURL = makeSpikeThumbnailURL() else {
        macWallNativeWallpaperLogger.warning("Falling back to empty settings because thumbnail generation failed")
        return makeSettingsViewModelsXPC(groups: [])
    }

    let choiceID = StubChoiceID(
        id: spikeChoiceIdentifier,
        descriptor: StubChoiceIDDescriptor(
            provider: StubChoiceProviderID(rawValue: bundleID),
            identifier: spikeChoiceIdentifier,
            files: [thumbnailURL],
            configuration: Data(spikeChoiceIdentifier.utf8)
        )
    )

    let choiceDescriptor = StubChoiceDescriptor(
        id: choiceID,
        provider: StubChoiceProviderID(rawValue: bundleID),
        identifier: spikeChoiceIdentifier,
        name: "MacWall Native Spike",
        localizedDescription: "Native WallpaperAgent handshake probe",
        thumbnail: .image(url: thumbnailURL),
        isDownloaded: true,
        options: []
    )

    let item = StubSettingsItem(
        id: choiceID,
        localizedName: "MacWall Native Spike",
        thumbnail: .image(url: thumbnailURL),
        choice: choiceDescriptor,
        contentBadge: .dynamic,
        showInTopLevel: true,
        sortOrder: 0,
        disposability: .none
    )

    let group = StubSettingsGroup(
        id: StubGroupID(id: "macwall-native-wallpaper-spike"),
        items: [item],
        localizedName: "MacWall",
        disposability: .none,
        sortOrder: -100,
        sortID: StubGroupSortID(id: "com.apple.wallpaper.aerials"),
        allChoiceID: nil,
        shouldHideItemLabels: false,
        contextMenu: nil,
        thumbnail: nil
    )

    return makeSettingsViewModelsXPC(groups: [group])
}

private func makeSettingsViewModelsXPC(groups: [StubSettingsGroup]) -> AnyObject? {
    let viewModels = StubSettingsViewModels(
        desktop: StubSettingsViewModel(
            groups: groups,
            refreshPolicy: .default,
            isModificationDisabled: false
        ),
        screenSaver: nil
    )

    let shim = MacWallSettingsViewModelsShimXPC(value: viewModels)
    let data: Data

    do {
        data = try NSKeyedArchiver.archivedData(withRootObject: shim, requiringSecureCoding: false)
    } catch {
        macWallNativeWallpaperLogger.error("Settings view model archive failed: \(String(describing: error), privacy: .public)")
        return nil
    }

    guard let realClass = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass else {
        macWallNativeWallpaperLogger.warning("WallpaperSettingsViewModelsXPC class is unavailable; replying with nil settings model")
        return nil
    }

    do {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(realClass, forClassName: "MacWallSettingsViewModelsShimXPC")

        let object = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        if let error = unarchiver.error {
            macWallNativeWallpaperLogger.warning("Settings view model unarchive warning: \(String(describing: error), privacy: .public)")
        }
        unarchiver.finishDecoding()

        if let object {
            macWallNativeWallpaperLogger.info("Created WallpaperSettingsViewModelsXPC groups=\(groups.count)")
            return object as AnyObject
        }

        macWallNativeWallpaperLogger.warning("Settings view model unarchived to nil")
        return nil
    } catch {
        macWallNativeWallpaperLogger.error("Settings view model unarchiver creation failed: \(String(describing: error), privacy: .public)")
        return nil
    }
}

private func makeSpikeThumbnailURL() -> URL? {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacWallNativeWallpaperSpike", isDirectory: true)
    let url = directory.appendingPathComponent("thumbnail.png")

    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let width = 256
        let height = 160
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.10, green: 0.36, blue: 0.90, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0.52, green: 0.18, blue: 0.88, alpha: 1))
        context.fill(CGRect(x: width / 3, y: height / 4, width: width / 2, height: height / 2))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return url
    } catch {
        macWallNativeWallpaperLogger.error("Thumbnail generation failed: \(String(describing: error), privacy: .public)")
        return nil
    }
}

private struct StubSettingsViewModels: Codable {
    var desktop: StubSettingsViewModel?
    var screenSaver: StubSettingsViewModel?
}

private struct StubSettingsViewModel: Codable {
    var groups: [StubSettingsGroup]
    var refreshPolicy: StubRefreshPolicy
    var isModificationDisabled: Bool
}

private struct StubSettingsGroup: Codable {
    var id: StubGroupID
    var items: [StubSettingsItem]
    var localizedName: String
    var disposability: StubDisposability
    var sortOrder: Int
    var sortID: StubGroupSortID?
    var allChoiceID: StubChoiceID?
    var shouldHideItemLabels: Bool?
    var contextMenu: StubContextMenu?
    var thumbnail: Data?
}

private struct StubGroupID: Codable {
    var id: String
}

private struct StubGroupSortID: Codable {
    var id: String
}

private struct StubChoiceID: Codable {
    var id: String
    var descriptor: StubChoiceIDDescriptor
}

private struct StubChoiceIDDescriptor: Codable {
    var provider: StubChoiceProviderID
    var identifier: String
    var files: [URL]
    var configuration: Data
}

private struct StubSettingsItem: Codable {
    var id: StubChoiceID
    var localizedName: String
    var thumbnail: StubThumbnail
    var choice: StubChoiceDescriptor
    var contentBadge: StubContentBadge
    var showInTopLevel: Bool
    var sortOrder: Int
    var disposability: StubDisposability
}

private struct StubChoiceDescriptor: Codable {
    var id: StubChoiceID
    var provider: StubChoiceProviderID
    var identifier: String
    var name: String?
    var localizedDescription: String
    var thumbnail: StubThumbnail
    var isDownloaded: Bool
    var options: [StubWallpaperOption]
}

private struct StubWallpaperOption: Codable {}

private struct StubChoiceProviderID: Codable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }
}

private enum StubThumbnail: Codable {
    case image(url: URL)

    private enum CodingKeys: String, CodingKey {
        case image
    }

    private enum ImageCodingKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .image(url):
            var nested = container.nestedContainer(keyedBy: ImageCodingKeys.self, forKey: .image)
            try nested.encode(url, forKey: .url)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.nestedContainer(keyedBy: ImageCodingKeys.self, forKey: .image)
        self = .image(url: try nested.decode(URL.self, forKey: .url))
    }
}

private enum StubContentBadge: Codable {
    case none
    case video
    case dynamic

    private enum CodingKeys: String, CodingKey {
        case none
        case video
        case dynamic
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .none)
        case .video:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .video)
        case .dynamic:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .dynamic)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.dynamic) {
            self = .dynamic
        } else if container.contains(.video) {
            self = .video
        } else {
            self = .none
        }
    }
}

private enum StubDisposability: Codable {
    case none
    case removable
    case purgeable

    private enum CodingKeys: String, CodingKey {
        case none
        case removable
        case purgeable
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .none)
        case .removable:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .removable)
        case .purgeable:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .purgeable)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.removable) {
            self = .removable
        } else if container.contains(.purgeable) {
            self = .purgeable
        } else {
            self = .none
        }
    }
}

private enum StubRefreshPolicy: Codable {
    case `default`

    private enum CodingKeys: String, CodingKey {
        case `default`
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .default)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.default) {
            self = .default
        } else {
            self = .default
        }
    }
}

private struct StubContextMenu: Codable {
    var items: [StubContextMenuItem]
}

private struct StubContextMenuItem: Codable {
    var identifier: String
    var name: String
}

private enum EmptyCodingKeys: CodingKey {}

@objc(MacWallSettingsViewModelsShimXPC)
private final class MacWallSettingsViewModelsShimXPC: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true

    private let value: StubSettingsViewModels

    init(value: StubSettingsViewModels) {
        self.value = value
        super.init()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func encode(with coder: NSCoder) {
        guard let archiver = coder as? NSKeyedArchiver else {
            macWallNativeWallpaperLogger.error("Settings view model encode failed: coder is not NSKeyedArchiver")
            return
        }

        do {
            try archiver.encodeEncodable(value, forKey: "WallpaperSettingsViewModels")
        } catch {
            macWallNativeWallpaperLogger.error("Settings view model encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}
