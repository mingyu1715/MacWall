import Foundation

enum Fixture {
    static func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "wwb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeWorkshopRoot() throws -> URL {
        let root = try makeTempDirectory()
            .appending(path: "steamapps")
            .appending(path: "workshop")
            .appending(path: "content")
            .appending(path: "431960")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func project(root: URL, id: String, metadata: String, file: String) throws {
        let project = root.appending(path: id)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try metadata.write(to: project.appending(path: "project.json"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: project.appending(path: file).path, contents: Data())
    }

    static func writeScenePackage(
        to url: URL,
        sceneJSON: String,
        extraEntries: [(path: String, data: Data)] = []
    ) throws {
        var entries = [(path: "scene.json", data: Data(sceneJSON.utf8))]
        entries.append(contentsOf: extraEntries)
        try scenePackageData(entries: entries).write(to: url, options: [.atomic])
    }

    static func scenePackageData(
        magic: String = "PKGV0007",
        entries: [(path: String, data: Data)]
    ) -> Data {
        var data = Data()
        data.appendLengthPrefixedString(magic)
        data.appendInt32(entries.count)
        var offset = 0
        for entry in entries {
            data.appendLengthPrefixedString(entry.path)
            data.appendInt32(offset)
            data.appendInt32(entry.data.count)
            offset += entry.data.count
        }
        for entry in entries {
            data.append(entry.data)
        }
        return data
    }

    static func texData(
        width: Int,
        height: Int,
        imageFormat: Int = 13,
        imageData: Data
    ) -> Data {
        var data = Data()
        data.appendNullTerminatedString("TEXV0005")
        data.appendNullTerminatedString("TEXI0001")
        data.appendInt32(0)
        data.appendInt32(0)
        data.appendInt32(width)
        data.appendInt32(height)
        data.appendInt32(width)
        data.appendInt32(height)
        data.appendUInt32(0)
        data.appendNullTerminatedString("TEXB0003")
        data.appendInt32(1)
        data.appendInt32(imageFormat)
        data.appendInt32(1)
        data.appendInt32(width)
        data.appendInt32(height)
        data.appendInt32(0)
        data.appendInt32(0)
        data.appendInt32(imageData.count)
        data.append(imageData)
        return data
    }
}

private extension Data {
    mutating func appendInt32(_ value: Int) {
        var raw = Int32(value).littleEndian
        Swift.withUnsafeBytes(of: &raw) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var raw = value.littleEndian
        Swift.withUnsafeBytes(of: &raw) { append(contentsOf: $0) }
    }

    mutating func appendLengthPrefixedString(_ string: String) {
        let bytes = Data(string.utf8)
        appendInt32(bytes.count)
        append(bytes)
    }

    mutating func appendNullTerminatedString(_ string: String) {
        append(Data(string.utf8))
        append(0)
    }
}
