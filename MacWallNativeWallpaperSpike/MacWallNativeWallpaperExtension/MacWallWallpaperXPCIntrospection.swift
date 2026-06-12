import Foundation

func logXPCObject(_ label: String, _ value: Any?) {
    for line in describeXPCObject(label: label, value: value) {
        macWallNativeWallpaperLogger.info("\(line, privacy: .public)")
    }
}

private func describeXPCObject(label: String, value: Any?) -> [String] {
    guard let value else {
        return ["\(label): nil"]
    }

    var lines: [String] = []
    appendDescription(label: label, value: value, depth: 0, lines: &lines)
    return lines
}

private func appendDescription(label: String, value: Any, depth: Int, lines: inout [String]) {
    let indent = String(repeating: "  ", count: depth)
    let typeName = objectTypeName(value)
    let summary = truncate(String(describing: value), limit: depth == 0 ? 900 : 360)
    lines.append("\(indent)\(label): type=\(typeName) value=\(summary)")

    guard depth < 3 else {
        return
    }

    let mirror = Mirror(reflecting: value)
    guard !mirror.children.isEmpty else {
        return
    }

    let children = Array(mirror.children)
    for child in children.prefix(12) {
        let childLabel = child.label ?? "<unlabeled>"
        appendDescription(label: ".\(childLabel)", value: child.value, depth: depth + 1, lines: &lines)
    }

    if children.count > 12 {
        lines.append("\(indent)  ... \(children.count - 12) more children")
    }
}

private func objectTypeName(_ value: Any) -> String {
    if let object = value as? NSObject {
        return NSStringFromClass(type(of: object))
    }
    return String(reflecting: type(of: value))
}

private func truncate(_ text: String, limit: Int) -> String {
    guard text.count > limit else {
        return text
    }

    let index = text.index(text.startIndex, offsetBy: limit)
    return String(text[..<index]) + "...<truncated>"
}
