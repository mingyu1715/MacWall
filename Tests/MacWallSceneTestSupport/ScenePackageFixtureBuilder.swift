import Foundation

public struct ScenePackageFixtureEntry: Sendable {
    public let path: String
    public let data: Data
    public let tableOffset: Int32?
    public let tableLength: Int32?

    public init(
        path: String,
        data: Data,
        tableOffset: Int32? = nil,
        tableLength: Int32? = nil
    ) {
        self.path = path
        self.data = data
        self.tableOffset = tableOffset
        self.tableLength = tableLength
    }
}

public enum ScenePackageFixtureBuilder {
    public static func make(
        version: String = "PKGV0008",
        entries: [ScenePackageFixtureEntry]
    ) -> Data {
        var result = Data()
        result.appendLengthPrefixedString(version)
        result.appendInt32(Int32(entries.count))

        var nextOffset: Int32 = 0
        for entry in entries {
            result.appendLengthPrefixedString(entry.path)
            result.appendInt32(entry.tableOffset ?? nextOffset)
            result.appendInt32(
                entry.tableLength ?? Int32(entry.data.count)
            )
            nextOffset += Int32(entry.data.count)
        }
        for entry in entries {
            result.append(entry.data)
        }
        return result
    }

    public static func write(
        to url: URL,
        version: String = "PKGV0008",
        sceneJSON: String,
        extraEntries: [ScenePackageFixtureEntry] = []
    ) throws {
        var entries = [
            ScenePackageFixtureEntry(
                path: "scene.json",
                data: Data(sceneJSON.utf8)
            )
        ]
        entries.append(contentsOf: extraEntries)
        try make(version: version, entries: entries)
            .write(to: url, options: [.atomic])
    }
}

private extension Data {
    mutating func appendInt32(_ value: Int32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLengthPrefixedString(_ value: String) {
        let bytes = Data(value.utf8)
        appendInt32(Int32(bytes.count))
        append(bytes)
    }
}
