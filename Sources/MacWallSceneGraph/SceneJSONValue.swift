import CoreFoundation
import Foundation

public enum SceneJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([SceneJSONValue])
    case object([String: SceneJSONValue])
}

extension SceneJSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: SceneJSONValueCodingKey.self
        )
        let kind = try container.decode(
            SceneJSONValueKind.self,
            forKey: .kind
        )

        switch kind {
        case .null:
            self = .null
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int64.self, forKey: .value))
        case .number:
            let value = try container.decode(Double.self, forKey: .value)
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "JSON numbers must be finite."
                )
            }
            self = .number(value)
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .array:
            var valueContainer = try container.nestedUnkeyedContainer(
                forKey: .value
            )
            var values: [SceneJSONValue] = []
            while !valueContainer.isAtEnd {
                values.append(try valueContainer.decode(SceneJSONValue.self))
            }
            self = .array(values)
        case .object:
            let valueContainer = try container.nestedContainer(
                keyedBy: SceneJSONCodingKey.self,
                forKey: .value
            )
            var object: [String: SceneJSONValue] = [:]
            object.reserveCapacity(valueContainer.allKeys.count)

            for key in valueContainer.allKeys {
                object[key.stringValue] = try valueContainer.decode(
                    SceneJSONValue.self,
                    forKey: key
                )
            }
            self = .object(object)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SceneJSONValueCodingKey.self)

        switch self {
        case .null:
            try container.encode(SceneJSONValueKind.null, forKey: .kind)
        case let .bool(value):
            try container.encode(SceneJSONValueKind.bool, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode(SceneJSONValueKind.integer, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .number(value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "JSON numbers must be finite."
                    )
                )
            }
            try container.encode(SceneJSONValueKind.number, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(SceneJSONValueKind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .array(value):
            try container.encode(SceneJSONValueKind.array, forKey: .kind)
            var valueContainer = container.nestedUnkeyedContainer(forKey: .value)
            for child in value {
                try valueContainer.encode(child)
            }
        case let .object(value):
            try container.encode(SceneJSONValueKind.object, forKey: .kind)
            var valueContainer = container.nestedContainer(
                keyedBy: SceneJSONCodingKey.self,
                forKey: .value
            )
            for (key, child) in value {
                try valueContainer.encode(child, forKey: SceneJSONCodingKey(key))
            }
        }
    }
}

enum SceneJSONDocumentError: Error, Equatable {
    case malformed
    case depthLimit(maximum: Int)
}

struct SceneJSONDocumentDecoder {
    let maximumDepth: Int

    func decode(_ data: Data) throws -> SceneJSONValue {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw SceneJSONDocumentError.malformed
        }

        try validateDepth(of: root)
        return try convert(root)
    }

    private func validateDepth(of root: Any) throws {
        var pending: [(value: Any, depth: Int)] = [(root, 0)]

        while let current = pending.popLast() {
            guard current.depth <= maximumDepth else {
                throw SceneJSONDocumentError.depthLimit(maximum: maximumDepth)
            }

            if let object = current.value as? [String: Any] {
                pending.append(
                    contentsOf: object.values.map {
                        (value: $0, depth: current.depth + 1)
                    }
                )
            } else if let array = current.value as? [Any] {
                pending.append(
                    contentsOf: array.map {
                        (value: $0, depth: current.depth + 1)
                    }
                )
            }
        }
    }

    private func convert(_ value: Any) throws -> SceneJSONValue {
        if value is NSNull {
            return .null
        }

        let typeID = CFGetTypeID(value as CFTypeRef)
        if typeID == CFBooleanGetTypeID() {
            return .bool(value as! Bool)
        }

        if typeID == CFNumberGetTypeID() {
            return try convertNumber(value as! CFNumber)
        }

        if let string = value as? String {
            return .string(string)
        }

        if let array = value as? [Any] {
            return try .array(array.map(convert))
        }

        if let object = value as? [String: Any] {
            var converted: [String: SceneJSONValue] = [:]
            converted.reserveCapacity(object.count)
            for (key, child) in object {
                converted[key] = try convert(child)
            }
            return .object(converted)
        }

        throw SceneJSONDocumentError.malformed
    }

    private func convertNumber(_ number: CFNumber) throws -> SceneJSONValue {
        if CFNumberIsFloatType(number) {
            let value = try doubleValue(from: number)
            guard value.isFinite else {
                throw SceneJSONDocumentError.malformed
            }
            return .number(value)
        }

        var integer: Int64 = 0
        if CFNumberGetValue(number, .sInt64Type, &integer) {
            return .integer(integer)
        }

        let value = try doubleValue(from: number)
        guard value.isFinite else {
            throw SceneJSONDocumentError.malformed
        }
        return .number(value)
    }

    private func doubleValue(from number: CFNumber) throws -> Double {
        var value: Double = 0
        guard CFNumberGetValue(number, .float64Type, &value) else {
            throw SceneJSONDocumentError.malformed
        }
        return value
    }
}

private struct SceneJSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum SceneJSONValueCodingKey: String, CodingKey {
    case kind
    case value
}

private enum SceneJSONValueKind: String, Codable {
    case null
    case bool
    case integer
    case number
    case string
    case array
    case object
}
