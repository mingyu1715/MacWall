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
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "JSON numbers must be finite."
                )
            }
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SceneJSONValue].self) {
            self = .array(value)
        } else {
            let objectContainer = try decoder.container(
                keyedBy: SceneJSONCodingKey.self
            )
            var object: [String: SceneJSONValue] = [:]
            object.reserveCapacity(objectContainer.allKeys.count)

            for key in objectContainer.allKeys {
                object[key.stringValue] = try objectContainer.decode(
                    SceneJSONValue.self,
                    forKey: key
                )
            }
            self = .object(object)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
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
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .array(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .object(value):
            var container = encoder.container(keyedBy: SceneJSONCodingKey.self)
            for (key, child) in value {
                try container.encode(child, forKey: SceneJSONCodingKey(key))
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
