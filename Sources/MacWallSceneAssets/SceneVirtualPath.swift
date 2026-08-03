import Foundation

public enum SceneVirtualPathError: Error, Equatable, Sendable {
    case empty
    case absolute
    case backslash
    case nul
    case emptyComponent
    case escapesRoot
}

public struct SceneVirtualPath: Codable, Comparable, Hashable, Sendable {
    public let rawValue: String

    private static let maximumUTF8ByteCount = 4_096

    public init(canonicalPath: String) throws {
        let components = try Self.validatedComponents(
            in: canonicalPath,
            allowingDotSegments: false
        )
        guard !components.isEmpty else {
            throw SceneVirtualPathError.empty
        }
        rawValue = components.joined(separator: "/")
    }

    public static func resolving(
        reference: String,
        relativeTo owner: SceneVirtualPath?
    ) throws -> SceneVirtualPath {
        let referenceComponents = try validatedComponents(
            in: reference,
            allowingDotSegments: true
        )
        var components = owner?.rawValue.split(separator: "/").map(String.init) ?? []
        if owner != nil {
            _ = components.popLast()
        }

        for component in referenceComponents {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw SceneVirtualPathError.escapesRoot
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }

        return try SceneVirtualPath(
            canonicalPath: components.joined(separator: "/")
        )
    }

    public static func < (
        lhs: SceneVirtualPath,
        rhs: SceneVirtualPath
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(canonicalPath: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func validatedComponents(
        in path: String,
        allowingDotSegments: Bool
    ) throws -> [String] {
        guard !path.isEmpty else {
            throw SceneVirtualPathError.empty
        }
        guard path.utf8.count <= maximumUTF8ByteCount else {
            throw SceneVirtualPathError.emptyComponent
        }
        guard !path.hasPrefix("/") else {
            throw SceneVirtualPathError.absolute
        }
        guard !path.contains("\\") else {
            throw SceneVirtualPathError.backslash
        }
        guard !path.contains("\0") else {
            throw SceneVirtualPathError.nul
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: \.isEmpty) else {
            throw SceneVirtualPathError.emptyComponent
        }
        if !allowingDotSegments {
            guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
                throw SceneVirtualPathError.emptyComponent
            }
        }
        return components
    }
}
