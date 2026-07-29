import Foundation

public enum NativeRuntimeConstants {
    public static let schemaVersion = 1
    public static let appGroupIdentifier = "group.com.mingyu1715.macwall"
    public static let changeNotificationName = "com.mingyu1715.macwall.native-runtime.changed"
    public static let transportInfoDictionaryKey = "MacWallNativeRuntimeTransport"
    public static let developmentRuntimeDirectoryComponents = [
        "Library",
        "Application Support",
        "MacWall",
        "NativeRuntimeAdHocQA"
    ]
}

public enum NativeRuntimeCommandKind: String, Codable, Sendable {
    case play
    case stop
}

public enum NativeRuntimeAssetKind: String, Codable, Sendable {
    case video
}

public enum NativeRuntimeDisplayMode: String, Codable, Sendable {
    case fit
    case fill
    case stretch
}

public struct NativeRuntimeCommand: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let kind: NativeRuntimeCommandKind
    public let generation: UUID
    public let assetID: String?
    public let assetKind: NativeRuntimeAssetKind?
    public let relativeSourcePath: String?
    public let displayMode: NativeRuntimeDisplayMode?
    public let createdAt: Date

    public static func play(
        generation: UUID,
        assetID: String,
        relativeSourcePath: String,
        displayMode: NativeRuntimeDisplayMode,
        createdAt: Date
    ) -> Self {
        Self(
            schemaVersion: NativeRuntimeConstants.schemaVersion,
            kind: .play,
            generation: generation,
            assetID: assetID,
            assetKind: .video,
            relativeSourcePath: relativeSourcePath,
            displayMode: displayMode,
            createdAt: createdAt
        )
    }

    public static func stop(generation: UUID, createdAt: Date) -> Self {
        Self(
            schemaVersion: NativeRuntimeConstants.schemaVersion,
            kind: .stop,
            generation: generation,
            assetID: nil,
            assetKind: nil,
            relativeSourcePath: nil,
            displayMode: nil,
            createdAt: createdAt
        )
    }

    private init(
        schemaVersion: Int,
        kind: NativeRuntimeCommandKind,
        generation: UUID,
        assetID: String?,
        assetKind: NativeRuntimeAssetKind?,
        relativeSourcePath: String?,
        displayMode: NativeRuntimeDisplayMode?,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.generation = generation
        self.assetID = assetID
        self.assetKind = assetKind
        self.relativeSourcePath = relativeSourcePath
        self.displayMode = displayMode
        self.createdAt = createdAt
    }
}

public enum NativeRuntimeStatusState: String, Codable, Sendable {
    case inactive
    case preparing
    case playing
    case stopped
    case failed
}

public struct NativeRuntimeFailure: Codable, Equatable, Sendable {
    public let category: String
    public let code: String
    public let message: String

    public init(category: String, code: String, message: String) {
        self.category = category
        self.code = code
        self.message = message
    }
}

public struct NativeRuntimeStatus: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestedGeneration: UUID?
    public let activeGeneration: UUID?
    public let state: NativeRuntimeStatusState
    public let activeDesktopContextCount: Int
    public let extensionInstanceID: UUID
    public let processIdentifier: Int32
    public let heartbeatAt: Date
    public let failure: NativeRuntimeFailure?

    public init(
        schemaVersion: Int = NativeRuntimeConstants.schemaVersion,
        requestedGeneration: UUID?,
        activeGeneration: UUID?,
        state: NativeRuntimeStatusState,
        activeDesktopContextCount: Int,
        extensionInstanceID: UUID,
        processIdentifier: Int32,
        heartbeatAt: Date,
        failure: NativeRuntimeFailure?
    ) {
        self.schemaVersion = schemaVersion
        self.requestedGeneration = requestedGeneration
        self.activeGeneration = activeGeneration
        self.state = state
        self.activeDesktopContextCount = activeDesktopContextCount
        self.extensionInstanceID = extensionInstanceID
        self.processIdentifier = processIdentifier
        self.heartbeatAt = heartbeatAt
        self.failure = failure
    }
}

public enum NativeRuntimeStoreError: Error, Equatable {
    case appGroupUnavailable
    case transportConfigurationMissing
    case unsupportedTransportConfiguration(String)
    case accountHomeUnavailable
    case unsupportedSchema(Int)
    case invalidCommand
    case invalidSourcePath
    case sourceMissing
    case generationAlreadyExists
    case unsafeSymbolicLink
}
