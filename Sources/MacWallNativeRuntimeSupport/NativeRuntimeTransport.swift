import Darwin
import Foundation

public enum NativeRuntimeTransportMode: String, Sendable {
    case appGroup = "app-group"
    case developmentHome = "development-home"

    public init(configurationValue: String?) throws {
        guard let configurationValue, !configurationValue.isEmpty else {
            throw NativeRuntimeStoreError.transportConfigurationMissing
        }
        guard let mode = Self(rawValue: configurationValue) else {
            throw NativeRuntimeStoreError.unsupportedTransportConfiguration(
                configurationValue
            )
        }
        self = mode
    }

    public static func configured(in bundle: Bundle = .main) throws -> Self {
        try Self(
            configurationValue: bundle.object(
                forInfoDictionaryKey: NativeRuntimeConstants.transportInfoDictionaryKey
            ) as? String
        )
    }
}

public protocol NativeRuntimeRootResolving: Sendable {
    func rootURL(for mode: NativeRuntimeTransportMode) throws -> URL
}

public struct NativeRuntimeRootResolver: NativeRuntimeRootResolving {
    private let appGroupContainerURL: @Sendable (String) -> URL?
    private let accountHomeDirectoryURL: @Sendable () throws -> URL

    public init(
        appGroupContainerURL: @escaping @Sendable (String) -> URL?,
        accountHomeDirectoryURL: @escaping @Sendable () throws -> URL
    ) {
        self.appGroupContainerURL = appGroupContainerURL
        self.accountHomeDirectoryURL = accountHomeDirectoryURL
    }

    public static var live: Self {
        Self(
            appGroupContainerURL: { identifier in
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: identifier
                )
            },
            accountHomeDirectoryURL: Self.currentAccountHomeDirectoryURL
        )
    }

    public func rootURL(for mode: NativeRuntimeTransportMode) throws -> URL {
        switch mode {
        case .appGroup:
            guard let container = appGroupContainerURL(
                NativeRuntimeConstants.appGroupIdentifier
            ) else {
                throw NativeRuntimeStoreError.appGroupUnavailable
            }
            return container.appending(path: "NativeRuntime")
        case .developmentHome:
            return try NativeRuntimeConstants
                .developmentRuntimeDirectoryComponents
                .reduce(accountHomeDirectoryURL()) { url, component in
                    url.appending(path: component)
                }
        }
    }

    private static func currentAccountHomeDirectoryURL() throws -> URL {
        let queriedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        let capacity = queriedSize > 0 ? Int(queriedSize) : 16_384
        var buffer = [CChar](repeating: 0, count: capacity)

        return try buffer.withUnsafeMutableBufferPointer { pointer in
            var entry = passwd()
            var result: UnsafeMutablePointer<passwd>?
            let status = getpwuid_r(
                getuid(),
                &entry,
                pointer.baseAddress,
                pointer.count,
                &result
            )
            guard status == 0,
                  result != nil,
                  let home = entry.pw_dir else {
                throw NativeRuntimeStoreError.accountHomeUnavailable
            }
            return URL(
                filePath: String(cString: home),
                directoryHint: .isDirectory
            )
        }
    }
}
