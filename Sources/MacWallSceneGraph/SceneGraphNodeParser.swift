import Foundation
import MacWallSceneAssets

struct SceneGraphNodeParser: Sendable {
    let sourcePath: SceneVirtualPath

    func parse(
        _ rawValue: SceneJSONValue,
        at index: Int
    ) -> SceneGraphParsedNode {
        let nodeID = SceneNodeID(documentPath: sourcePath, objectIndex: index)
        guard case let .object(object) = rawValue else {
            return SceneGraphParsedNode(
                node: unknownNode(
                    id: nodeID,
                    sourceOrder: index,
                    rawValue: rawValue,
                    unknownFields: [:]
                ),
                diagnostics: [
                    invalidProperty(nodeID: nodeID, path: "objects[\(index)]"),
                    unknownNode(nodeID: nodeID, typeName: nil)
                ]
            )
        }

        var fields = object
        let sourceIdentifier = parseSourceIdentifier(
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        consumeRepresentedHierarchyMetadata(from: &fields)
        let name = parseString(
            key: "name",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let visible = parseBool(
            key: "visible",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let enabled = parseBool(
            key: "enabled",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let origin = parseVector3(
            key: "origin",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let pivot = parseVector3(
            key: "pivot",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let position = parseVector3(
            key: "position",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let scale = parseVector3(
            key: "scale",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let angles = parseVector3(
            key: "angles",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let size = parseSize(
            key: "size",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let opacity = parseNumber(
            key: "alpha",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let color = parseColor(
            key: "color",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let zOrder = parseZOrder(
            from: &fields,
            nodeID: nodeID,
            index: index
        )
        let payload = parsePayload(
            from: &fields,
            rawValue: rawValue,
            nodeID: nodeID,
            index: index
        )

        var diagnostics = invalidProperties(
            fields: fields,
            nodeID: nodeID,
            index: index
        )
        if case let .unknown(typeName, _) = payload {
            diagnostics.append(unknownNode(nodeID: nodeID, typeName: typeName))
        }
        let unknownFields = fields
        diagnostics.append(contentsOf: fields.keys.filter {
            !SceneGraphNodeParser.consumedKeys.contains($0)
                && !SceneGraphNodeParser.resolverManagedKeys.contains($0)
        }.sorted().map {
            invalidProperty(
                nodeID: nodeID,
                path: "objects[\(index)].\($0)"
            )
        })

        return SceneGraphParsedNode(
            node: SceneGraphNode(
                id: nodeID,
                sourceIdentifier: sourceIdentifier.value,
                sourceOrder: index,
                name: name.value,
                payload: payload,
                visible: visible.value,
                enabled: enabled.value,
                zOrder: zOrder.value,
                origin: origin.value,
                pivot: pivot.value,
                position: position.value,
                scale: scale.value,
                angles: angles.value,
                size: size.value,
                opacity: opacity.value,
                color: color.value,
                unknownFields: unknownFields
            ),
            diagnostics: diagnostics
        )
    }

    private static let consumedKeys: Set<String> = [
        "id", "name", "visible", "enabled", "origin", "pivot", "position",
        "scale", "angles", "size", "alpha", "color", "zorder", "zindex",
        "image", "text", "particle", "sound", "model", "composition",
        "fullscreen", "type"
    ]

    private static let resolverManagedKeys: Set<String> = [
        "parent", "instance", "instanceoverride"
    ]

    private func parseSourceIdentifier(
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<SceneSourceIdentifier> {
        guard let value = fields["id"] else {
            return .init(value: nil, isValid: true)
        }
        if let identifier = SceneSourceIdentifier(scalar: value) {
            fields.removeValue(forKey: "id")
            return .init(value: identifier, isValid: true)
        }
        return .init(value: nil, isValid: false)
    }

    private func consumeRepresentedHierarchyMetadata(
        from fields: inout [String: SceneJSONValue]
    ) {
        if let parent = fields["parent"],
           SceneSourceIdentifier(scalar: parent) != nil {
            fields.removeValue(forKey: "parent")
        }

        guard let instance = fields["instance"],
              SceneSourceIdentifier(scalar: instance) != nil else {
            return
        }
        fields.removeValue(forKey: "instance")

        if let overrides = fields["instanceoverride"],
           SceneGraphInstanceOverrideParser.parse(overrides).isComplete {
            fields.removeValue(forKey: "instanceoverride")
        }
    }

    private func parseString(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<String> {
        parse(key: key, from: &fields) { value in
            guard case let .string(string) = value else {
                return nil
            }
            return string
        }
    }

    private func parseBool(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<Bool> {
        parse(key: key, from: &fields) { value in
            guard case let .bool(bool) = value else {
                return nil
            }
            return bool
        }
    }

    private func parseNumber(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<Double> {
        parse(key: key, from: &fields) { $0.finiteNumber }
    }

    private func parseVector3(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<SceneGraphVector3> {
        parse(key: key, from: &fields) { value in
            guard let components = vectorComponents(value, count: 3) else {
                return nil
            }
            return SceneGraphVector3(
                x: components[0], y: components[1], z: components[2]
            )
        }
    }

    private func parseSize(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<SceneGraphSize> {
        parse(key: key, from: &fields) { value in
            guard let components = vectorComponents(value, count: 2) else {
                return nil
            }
            return SceneGraphSize(width: components[0], height: components[1])
        }
    }

    private func parseColor(
        key: String,
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<SceneGraphColor> {
        parse(key: key, from: &fields) { value in
            guard let components = vectorComponents(value, count: 4) else {
                return nil
            }
            return SceneGraphColor(
                red: components[0],
                green: components[1],
                blue: components[2],
                alpha: components[3]
            )
        }
    }

    private func parseZOrder(
        from fields: inout [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneGraphParsedProperty<Double> {
        if fields["zorder"] != nil {
            return parseNumber(
                key: "zorder",
                from: &fields,
                nodeID: nodeID,
                index: index
            )
        }
        return parseNumber(
            key: "zindex",
            from: &fields,
            nodeID: nodeID,
            index: index
        )
    }

    private func parsePayload(
        from fields: inout [String: SceneJSONValue],
        rawValue: SceneJSONValue,
        nodeID: SceneNodeID,
        index: Int
    ) -> SceneNodePayload {
        for kind in SceneGraphNodeKind.ordered {
            if let value = fields[kind.key] {
                if isValidClassifierValue(value, for: kind) {
                    fields.removeValue(forKey: kind.key)
                }
                return payload(kind: kind, value: value, rawValue: rawValue)
            }
        }
        if case let .string(typeName)? = fields["type"] {
            fields.removeValue(forKey: "type")
            if let kind = SceneGraphNodeKind(rawValue: typeName) {
                return payload(kind: kind, value: nil, rawValue: rawValue)
            }
            return .unknown(typeName: typeName, rawValue: rawValue)
        }
        return .unknown(typeName: nil, rawValue: rawValue)
    }

    private func isValidClassifierValue(
        _ value: SceneJSONValue,
        for kind: SceneGraphNodeKind
    ) -> Bool {
        switch kind {
        case .image, .particle, .sound, .model, .composition:
            optionalReference(from: value) != nil
        case .text, .fullscreen:
            true
        }
    }

    private func payload(
        kind: SceneGraphNodeKind,
        value: SceneJSONValue?,
        rawValue: SceneJSONValue
    ) -> SceneNodePayload {
        switch kind {
        case .image:
            .image(reference: reference(from: value))
        case .text:
            .text(value ?? .null)
        case .particle:
            .particle(reference: reference(from: value))
        case .sound:
            .sound(reference: reference(from: value))
        case .model:
            .model(reference: reference(from: value))
        case .composition:
            .composition(reference: optionalReference(from: value))
        case .fullscreen:
            .fullscreen
        }
    }

    private func reference(from value: SceneJSONValue?) -> String {
        optionalReference(from: value) ?? ""
    }

    private func optionalReference(from value: SceneJSONValue?) -> String? {
        guard let value else {
            return nil
        }
        if case let .string(reference) = unwrap(value) {
            return reference
        }
        return nil
    }

    private func parse<T>(
        key: String,
        from fields: inout [String: SceneJSONValue],
        transform: (SceneJSONValue) -> T?
    ) -> SceneGraphParsedProperty<T> {
        guard let rawValue = fields[key] else {
            return .init(value: nil, isValid: true)
        }
        guard let value = transform(unwrap(rawValue)) else {
            return .init(value: nil, isValid: false)
        }
        fields.removeValue(forKey: key)
        return .init(value: value, isValid: true)
    }

    private func invalidProperties(
        fields: [String: SceneJSONValue],
        nodeID: SceneNodeID,
        index: Int
    ) -> [SceneGraphParserDiagnostic] {
        SceneGraphNodeParser.consumedKeys.compactMap { key in
            guard fields[key] != nil else {
                return nil
            }
            return invalidProperty(
                nodeID: nodeID,
                path: "objects[\(index)].\(key)"
            )
        }
    }

    private func unknownNode(
        id: SceneNodeID,
        sourceOrder: Int,
        rawValue: SceneJSONValue,
        unknownFields: [String: SceneJSONValue]
    ) -> SceneGraphNode {
        SceneGraphNode(
            id: id,
            sourceIdentifier: nil,
            sourceOrder: sourceOrder,
            name: nil,
            payload: .unknown(typeName: nil, rawValue: rawValue),
            visible: nil,
            enabled: nil,
            zOrder: nil,
            origin: nil,
            pivot: nil,
            position: nil,
            scale: nil,
            angles: nil,
            size: nil,
            opacity: nil,
            color: nil,
            unknownFields: unknownFields
        )
    }

    private func invalidProperty(
        nodeID: SceneNodeID,
        path: String
    ) -> SceneGraphParserDiagnostic {
        .init(
            severity: .warning,
            code: "graph.invalid-property",
            sourcePath: sourcePath,
            nodeID: nodeID,
            jsonPath: path,
            arguments: [],
            evidence: .degraded
        )
    }

    private func unknownNode(
        nodeID: SceneNodeID,
        typeName: String?
    ) -> SceneGraphParserDiagnostic {
        .init(
            severity: .warning,
            code: "graph.unknown-node",
            sourcePath: sourcePath,
            nodeID: nodeID,
            jsonPath: "objects[\(nodeID.objectIndex)]",
            arguments: typeName.map { [$0] } ?? [],
            evidence: .unsupported
        )
    }

    private func unwrap(_ value: SceneJSONValue) -> SceneJSONValue {
        guard case let .object(object) = value,
              let wrapped = object["value"] else {
            return value
        }
        return wrapped
    }

    private func vectorComponents(
        _ value: SceneJSONValue,
        count: Int
    ) -> [Double]? {
        switch value {
        case let .array(values):
            let numbers = values.compactMap(\.finiteNumber)
            guard numbers.count == count, values.count == count else {
                return nil
            }
            return numbers
        case let .string(string):
            let values = string.split { character in
                character == "," || character == " " || character == "\t"
                    || character == "\n" || character == "\r"
                    || character == "\u{0B}" || character == "\u{0C}"
            }
            guard values.count == count else {
                return nil
            }
            let numbers = values.compactMap { Double($0) }
            guard numbers.count == count, numbers.allSatisfy(\.isFinite) else {
                return nil
            }
            return numbers
        default:
            return nil
        }
    }
}

struct SceneGraphParsedNode: Sendable {
    let node: SceneGraphNode
    let diagnostics: [SceneGraphParserDiagnostic]
}

struct SceneGraphParsedProperty<Value: Sendable>: Sendable {
    let value: Value?
    let isValid: Bool
}

struct SceneGraphParserDiagnostic: Sendable {
    let severity: SceneGraphDiagnosticSeverity
    let code: String
    let sourcePath: SceneVirtualPath?
    let nodeID: SceneNodeID?
    let jsonPath: String?
    let arguments: [String]
    let evidence: SceneGraphStatusEvidence
}

private enum SceneGraphNodeKind: String, CaseIterable {
    case image
    case text
    case particle
    case sound
    case model
    case composition
    case fullscreen

    static let ordered: [Self] = [
        .image, .text, .particle, .sound, .model, .composition, .fullscreen
    ]

    var key: String { rawValue }
}

private extension SceneJSONValue {
    var finiteNumber: Double? {
        switch self {
        case let .integer(value):
            Double(value)
        case let .number(value) where value.isFinite:
            value
        default:
            nil
        }
    }
}
