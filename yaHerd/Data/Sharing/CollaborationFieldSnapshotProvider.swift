import Foundation

/// Captures the same domain fields used by conflict review so revision metadata
/// can retain the last common field baseline and determine whether divergent
/// edits touch disjoint fields.
enum CollaborationFieldSnapshotProvider {
    static func snapshot(
        for aggregate: any CollaborativelyMutableAggregate
    ) -> CollaborationFieldSnapshot {
        switch aggregate {
        case let herd as Herd:
            return herdSnapshot(herd)
        case let definition as TagColorDefinition:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: definition)
        case let reference as AnimalStatusReference:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: reference)
        case let group as PastureGroup:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: group)
        case let pasture as Pasture:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: pasture)
        case let animal as Animal:
            return animalSnapshot(animal)
        case let tag as AnimalTag:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: tag)
        case let movement as MovementRecord:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: movement)
        case let record as StatusRecord:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: record)
        case let template as WorkingProtocolTemplate:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: template)
        case let session as WorkingSession:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: session)
        case let queueItem as WorkingQueueItem:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: queueItem)
        case let treatment as WorkingTreatmentRecord:
            return treatmentSnapshot(treatment)
        case let record as HealthRecord:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: record)
        case let check as PregnancyCheck:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: check)
        case let session as FieldCheckSession:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: session)
        case let check as FieldCheckAnimalCheck:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: check)
        case let finding as FieldCheckFinding:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: finding)
        default:
            return [:]
        }
    }

    private static func herdSnapshot(_ herd: Herd) -> CollaborationFieldSnapshot {
        [
            "name": value(herd.name),
            "createdAt": value(herd.createdAt),
            "updatedAt": value(herd.updatedAt),
            "schemaVersion": value(herd.schemaVersion),
        ]
    }

    private static func animalSnapshot(_ animal: Animal) -> CollaborationFieldSnapshot {
        var snapshot = HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: animal)
        snapshot["sireAnimalPublicID"] = value(animal.sireAnimal?.publicID)
        snapshot["damAnimalPublicID"] = value(animal.damAnimal?.publicID)
        return snapshot
    }

    /// Keep these names aligned with the bridge export schema. Treatment identity,
    /// dose unit, and route are semantic fields and must advance revision lineage.
    private static func treatmentSnapshot(
        _ treatment: WorkingTreatmentRecord
    ) -> CollaborationFieldSnapshot {
        [
            "date": value(treatment.date),
            "treatmentItemID": value(treatment.treatmentItemID),
            "itemName": value(treatment.itemName),
            "given": value(treatment.given),
            "doseAmount": value(treatment.doseAmount),
            "doseUnitRawValue": value(treatment.doseUnit?.rawValue),
            "administrationRouteRawValue": value(treatment.administrationRoute?.rawValue),
            "sessionPublicID": value(treatment.session?.publicID),
            "animalPublicID": value(treatment.animal?.publicID),
        ]
    }

    private static func value(_ value: String) -> HerdSharingBridgeConflictValue {
        HerdSharingBridgeConflictValue(type: .string, encodedValue: value)
    }

    private static func value(_ value: String?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        return HerdSharingBridgeConflictValue(type: .string, encodedValue: value)
    }

    private static func value(_ value: Bool) -> HerdSharingBridgeConflictValue {
        HerdSharingBridgeConflictValue(
            type: .bool,
            encodedValue: value ? "true" : "false"
        )
    }

    private static func value(_ value: Int) -> HerdSharingBridgeConflictValue {
        HerdSharingBridgeConflictValue(type: .int, encodedValue: String(value))
    }

    private static func value(_ value: Double?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        return HerdSharingBridgeConflictValue(type: .double, encodedValue: String(value))
    }

    private static func value(_ value: Date) -> HerdSharingBridgeConflictValue {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return HerdSharingBridgeConflictValue(
            type: .date,
            encodedValue: formatter.string(from: value)
        )
    }

    private static func value(_ value: UUID) -> HerdSharingBridgeConflictValue {
        HerdSharingBridgeConflictValue(type: .uuid, encodedValue: value.uuidString)
    }

    private static func value(_ value: UUID?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        return HerdSharingBridgeConflictValue(type: .uuid, encodedValue: value.uuidString)
    }
}
