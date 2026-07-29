import Foundation

enum Fixture {
    static func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "macwall-\(UUID().uuidString)")
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
}
