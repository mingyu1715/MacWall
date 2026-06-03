import Foundation

enum SourceFixture {
    private static let projectRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func contents(of relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
