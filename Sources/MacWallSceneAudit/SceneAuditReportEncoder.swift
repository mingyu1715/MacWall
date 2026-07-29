import Foundation

public enum SceneAuditReportEncoder {
    public static func encode(
        _ report: SceneAuditReport
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        var data = try encoder.encode(report)
        while data.last == 0x0A {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }
}
