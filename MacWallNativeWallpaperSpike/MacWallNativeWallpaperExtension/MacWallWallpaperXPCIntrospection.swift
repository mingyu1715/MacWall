import Foundation
import ObjectiveC

func logXPCObject(_ label: String, _ value: Any?) {
    for line in describeXPCObject(label: label, value: value) {
        macWallNativeWallpaperLogger.info("\(line, privacy: .public)")
    }
}

func logXPCShapeProbe(_ label: String, _ value: Any?) {
    let summary = describeXPCShapeProbe(label: label, value: value)
    macWallNativeWallpaperLogger.info("\(summary, privacy: .public)")
    logXPCShapeClassLayout(label: label, value: value)
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

private struct XPCShapeProbeSummary {
    var interestingLabels: [String] = []
    var urlCandidates: [String] = []
    var fileCandidates: [String] = []
    var tokenCandidates: [String] = []
    var descriptorCandidates: [String] = []
    var bookmarkCandidates: [String] = []
}

private let interestingFieldKeywords = [
    "access",
    "bookmark",
    "cache",
    "coordinat",
    "data",
    "descriptor",
    "directory",
    "export",
    "fd",
    "file",
    "handle",
    "home",
    "path",
    "raw",
    "sandbox",
    "scope",
    "security",
    "snapshot",
    "token",
    "url",
    "xpc",
]

private func describeXPCShapeProbe(label: String, value: Any?) -> String {
    guard let value else {
        return "shapeProbe label=\(label) value=nil interestingLabels=[] urlCandidates=[] fileCandidates=[] tokenCandidates=[] descriptorCandidates=[] bookmarkCandidates=[]"
    }

    var summary = XPCShapeProbeSummary()
    var visitedObjects = Set<ObjectIdentifier>()
    appendShapeProbe(
        path: label,
        value: value,
        depth: 0,
        visitedObjects: &visitedObjects,
        summary: &summary
    )

    return [
        "shapeProbe label=\(label)",
        "interestingLabels=\(format(summary.interestingLabels))",
        "urlCandidates=\(format(summary.urlCandidates))",
        "fileCandidates=\(format(summary.fileCandidates))",
        "tokenCandidates=\(format(summary.tokenCandidates))",
        "descriptorCandidates=\(format(summary.descriptorCandidates))",
        "bookmarkCandidates=\(format(summary.bookmarkCandidates))",
    ].joined(separator: " ")
}

private func appendShapeProbe(
    path: String,
    value: Any,
    depth: Int,
    visitedObjects: inout Set<ObjectIdentifier>,
    summary: inout XPCShapeProbeSummary
) {
    guard depth < 8, let unwrapped = unwrapOptionalForShape(value) else {
        return
    }

    if let object = unwrapped as? NSObject {
        let objectID = ObjectIdentifier(object)
        guard visitedObjects.insert(objectID).inserted else {
            return
        }
    }

    let normalizedPath = path.lowercased()
    let typeName = objectTypeName(unwrapped)
    let valueDescription = truncate(String(describing: unwrapped), limit: 220)

    if containsInterestingFieldKeyword(normalizedPath) {
        appendUnique("\(path):\(typeName)", to: &summary.interestingLabels)
    }

    if let url = urlValueForShape(unwrapped) {
        let candidate = "\(path)=\(url.absoluteString)"
        appendUnique(candidate, to: &summary.urlCandidates)
        appendUnique(candidate, to: &summary.fileCandidates)
    } else if looksLikeFileCandidate(normalizedPath: normalizedPath, typeName: typeName, valueDescription: valueDescription) {
        appendUnique("\(path):\(typeName)=\(valueDescription)", to: &summary.fileCandidates)
    }

    if looksLikeTokenCandidate(normalizedPath: normalizedPath, typeName: typeName, valueDescription: valueDescription) {
        appendUnique("\(path):\(typeName)=\(valueDescription)", to: &summary.tokenCandidates)
    }

    if looksLikeDescriptorCandidate(normalizedPath: normalizedPath, typeName: typeName, valueDescription: valueDescription) {
        appendUnique("\(path):\(typeName)=\(valueDescription)", to: &summary.descriptorCandidates)
    }

    if looksLikeBookmarkCandidate(normalizedPath: normalizedPath, typeName: typeName, valueDescription: valueDescription) {
        appendUnique("\(path):\(typeName)=\(valueDescription)", to: &summary.bookmarkCandidates)
    }

    let mirror = Mirror(reflecting: unwrapped)
    guard !mirror.children.isEmpty else {
        return
    }

    for child in mirror.children {
        let childLabel = child.label ?? "<unlabeled>"
        appendShapeProbe(
            path: "\(path).\(childLabel)",
            value: child.value,
            depth: depth + 1,
            visitedObjects: &visitedObjects,
            summary: &summary
        )
    }
}

private func containsInterestingFieldKeyword(_ text: String) -> Bool {
    interestingFieldKeywords.contains { text.contains($0) }
}

private func looksLikeFileCandidate(normalizedPath: String, typeName: String, valueDescription: String) -> Bool {
    normalizedPath.contains("file")
        || normalizedPath.contains("path")
        || normalizedPath.contains("directory")
        || normalizedPath.contains("cache")
        || normalizedPath.contains("home")
        || typeName.contains("NSURL")
        || valueDescription.contains("file://")
}

private func looksLikeTokenCandidate(normalizedPath: String, typeName: String, valueDescription: String) -> Bool {
    normalizedPath.contains("token")
        || normalizedPath.contains("access")
        || normalizedPath.contains("security")
        || normalizedPath.contains("scope")
        || normalizedPath.contains("sandbox")
        || typeName.lowercased().contains("token")
        || valueDescription.lowercased().contains("token")
}

private func looksLikeDescriptorCandidate(normalizedPath: String, typeName: String, valueDescription: String) -> Bool {
    normalizedPath.contains("descriptor")
        || normalizedPath.contains("fd")
        || normalizedPath.contains("handle")
        || typeName.lowercased().contains("descriptor")
        || valueDescription.lowercased().contains("descriptor")
}

private func looksLikeBookmarkCandidate(normalizedPath: String, typeName: String, valueDescription: String) -> Bool {
    normalizedPath.contains("bookmark")
        || normalizedPath.contains("securityscope")
        || valueDescription.lowercased().contains("bookmark")
        || (normalizedPath.contains("data") && normalizedPath.contains("url"))
        || typeName.contains("NSData")
}

private func appendUnique(_ value: String, to values: inout [String]) {
    guard values.count < 24, !values.contains(value) else {
        return
    }
    values.append(value)
}

private func format(_ values: [String]) -> String {
    "[" + values.joined(separator: " | ") + "]"
}

private func logXPCShapeClassLayout(label: String, value: Any?) {
    guard let value,
          let unwrapped = unwrapOptionalForShape(value),
          let object = unwrapped as? NSObject else {
        return
    }

    let objectClass: AnyClass = type(of: object)
    MacWallXPCShapeClassLayoutLogger.shared.log(objectClass, label: label)
}

private final class MacWallXPCShapeClassLayoutLogger: @unchecked Sendable {
    static let shared = MacWallXPCShapeClassLayoutLogger()

    private let lock = NSLock()
    private var loggedKeys: Set<String> = []

    private init() {}

    func log(_ objectClass: AnyClass, label: String) {
        let className = NSStringFromClass(objectClass)
        let key = "\(label)|\(className)"
        lock.lock()
        let shouldLog = loggedKeys.insert(key).inserted
        lock.unlock()
        guard shouldLog else {
            return
        }

        let ivars = describeIvars(of: objectClass)
        let methods = describeMethods(of: objectClass)
        macWallNativeWallpaperLogger.info(
            "shapeProbe classLayout label=\(label, privacy: .public) class=\(className, privacy: .public) ivars=\(ivars, privacy: .public) methods=\(methods, privacy: .public)"
        )
    }

    private func describeIvars(of objectClass: AnyClass) -> String {
        var count: UInt32 = 0
        guard let ivarList = class_copyIvarList(objectClass, &count) else {
            return "[]"
        }
        defer {
            free(ivarList)
        }

        var descriptions: [String] = []
        for index in 0..<Int(count) {
            let ivar = ivarList[index]
            guard let name = ivar_getName(ivar) else {
                continue
            }
            let typeEncoding = ivar_getTypeEncoding(ivar).map(String.init(cString:)) ?? "?"
            descriptions.append("\(String(cString: name)):\(typeEncoding)@\(ivar_getOffset(ivar))")
        }
        return "[" + descriptions.joined(separator: ",") + "]"
    }

    private func describeMethods(of objectClass: AnyClass) -> String {
        var count: UInt32 = 0
        guard let methodList = class_copyMethodList(objectClass, &count) else {
            return "[]"
        }
        defer {
            free(methodList)
        }

        var descriptions: [String] = []
        for index in 0..<min(Int(count), 80) {
            let selector = method_getName(methodList[index])
            descriptions.append(NSStringFromSelector(selector))
        }
        if count > 80 {
            descriptions.append("...\(count - 80) more")
        }
        return "[" + descriptions.joined(separator: ",") + "]"
    }
}

private func urlValueForShape(_ value: Any) -> URL? {
    guard let unwrapped = unwrapOptionalForShape(value) else {
        return nil
    }

    if let url = unwrapped as? URL {
        return url
    }

    if let nsURL = unwrapped as? NSURL {
        return nsURL as URL
    }

    return nil
}

private func unwrapOptionalForShape(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    return mirror.children.first?.value
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
