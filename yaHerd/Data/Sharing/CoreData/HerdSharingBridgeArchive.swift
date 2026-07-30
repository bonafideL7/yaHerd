import CoreData
import Foundation

enum HerdSharingBridgeArchiveValue: Hashable, Sendable {
    case null
    case string(String)
    case date(Date)
    case double(Double)
    case integer(Int64)
    case boolean(Bool)
    case data(Data)
}

struct HerdSharingBridgeRecordSnapshot: Hashable, Sendable {
    let entityName: String
    let publicID: String
    let herdPublicID: String?
    let attributes: [String: HerdSharingBridgeArchiveValue]

    var key: HerdSharingBridgeRecordKey {
        HerdSharingBridgeRecordKey(entityName: entityName, publicID: publicID)
    }
}

struct HerdSharingBridgeRecordKey: Hashable, Sendable {
    let entityName: String
    let publicID: String
}

struct HerdSharingBridgeArchive: Hashable, Sendable {
    let herd: HerdSummary
    let mirroredAt: Date
    let records: [HerdSharingBridgeRecordSnapshot]

    var recordsByEntityName: [String: [HerdSharingBridgeRecordSnapshot]] {
        Dictionary(grouping: records, by: \.entityName)
    }

    func records(named entityName: String) -> [HerdSharingBridgeRecordSnapshot] {
        records.filter { $0.entityName == entityName }
    }

    func publicIDs(named entityName: String) -> [UUID] {
        records(named: entityName).compactMap { UUID(uuidString: $0.publicID) }
    }
}

struct HerdSharingBridgeArchiveApplyResult: Sendable {
    let recordObjectIDURIs: [URL]
    let deletionTombstoneCount: Int
    let bridgePublicIDs: [HerdSharingBridgeStep: [UUID]]
}

enum HerdSharingBridgeArchiveCodec {
    static func snapshot(_ record: NSManagedObject) throws -> HerdSharingBridgeRecordSnapshot {
        guard let entityName = record.entity.name,
              let publicID = record.value(forKey: "publicID") as? String,
              !publicID.isEmpty else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "A bridge record could not be archived because its entity name or public ID was missing."
            )
        }

        var attributes: [String: HerdSharingBridgeArchiveValue] = [:]
        attributes.reserveCapacity(record.entity.attributesByName.count)

        for (name, attribute) in record.entity.attributesByName {
            attributes[name] = try archiveValue(
                record.value(forKey: name),
                attributeType: attribute.attributeType,
                fieldName: "\(entityName).\(name)"
            )
        }

        let herdPublicID: String?
        if record.entity.attributesByName["herdPublicID"] != nil {
            herdPublicID = record.value(forKey: "herdPublicID") as? String
        } else {
            herdPublicID = nil
        }

        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: publicID,
            herdPublicID: herdPublicID,
            attributes: attributes
        )
    }

    static func apply(
        _ snapshot: HerdSharingBridgeRecordSnapshot,
        to record: NSManagedObject
    ) throws {
        for (name, attribute) in record.entity.attributesByName {
            guard let value = snapshot.attributes[name] else {
                record.setValue(nil, forKey: name)
                continue
            }
            record.setValue(
                try managedValue(
                    value,
                    attributeType: attribute.attributeType,
                    fieldName: "\(snapshot.entityName).\(name)"
                ),
                forKey: name
            )
        }
    }

    private static func archiveValue(
        _ value: Any?,
        attributeType: NSAttributeType,
        fieldName: String
    ) throws -> HerdSharingBridgeArchiveValue {
        guard let value else { return .null }

        switch attributeType {
        case .stringAttributeType:
            guard let value = value as? String else { break }
            return .string(value)
        case .dateAttributeType:
            guard let value = value as? Date else { break }
            return .date(value)
        case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
            guard let value = value as? NSNumber else { break }
            return .double(value.doubleValue)
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            guard let value = value as? NSNumber else { break }
            return .integer(value.int64Value)
        case .booleanAttributeType:
            guard let value = value as? NSNumber else { break }
            return .boolean(value.boolValue)
        case .binaryDataAttributeType:
            guard let value = value as? Data else { break }
            return .data(value)
        case .UUIDAttributeType:
            guard let value = value as? UUID else { break }
            return .string(value.uuidString)
        case .URIAttributeType:
            guard let value = value as? URL else { break }
            return .string(value.absoluteString)
        default:
            break
        }

        throw HerdSharingActionError.bridgeConsistencyFailed(
            "Unsupported bridge archive value for \(fieldName)."
        )
    }

    private static func managedValue(
        _ value: HerdSharingBridgeArchiveValue,
        attributeType: NSAttributeType,
        fieldName: String
    ) throws -> Any? {
        switch value {
        case .null:
            return nil
        case .string(let value):
            switch attributeType {
            case .UUIDAttributeType:
                return UUID(uuidString: value)
            case .URIAttributeType:
                return URL(string: value)
            default:
                return value
            }
        case .date(let value):
            return value
        case .double(let value):
            return NSNumber(value: value)
        case .integer(let value):
            return NSNumber(value: value)
        case .boolean(let value):
            return NSNumber(value: value)
        case .data(let value):
            return value
        }
    }
}
