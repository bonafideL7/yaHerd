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
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: definition),
                preciseDates: [
                    "createdAt": definition.createdAt,
                    "updatedAt": definition.updatedAt,
                ]
            )
        case let reference as AnimalStatusReference:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: reference),
                preciseDates: ["createdAt": reference.createdAt]
            )
        case let group as PastureGroup:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: group)
        case let pasture as Pasture:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: pasture),
                preciseDates: ["lastGrazedDate": pasture.lastGrazedDate]
            )
        case let animal as Animal:
            return animalSnapshot(animal)
        case let tag as AnimalTag:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: tag),
                preciseDates: [
                    "assignedAt": tag.assignedAt,
                    "removedAt": tag.removedAt,
                ]
            )
        case let movement as MovementRecord:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: movement),
                preciseDates: ["date": movement.date]
            )
        case let record as StatusRecord:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: record),
                preciseDates: ["date": record.date]
            )
        case let template as WorkingProtocolTemplate:
            return HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: template)
        case let session as WorkingSession:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: session),
                preciseDates: ["date": session.date],
                excluding: ["currentQueueIndex"]
            )
        case let queueItem as WorkingQueueItem:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: queueItem),
                preciseDates: ["completedAt": queueItem.completedAt],
                excluding: ["queueOrder"]
            )
        case let treatment as WorkingTreatmentRecord:
            return treatmentSnapshot(treatment)
        case let record as HealthRecord:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: record),
                preciseDates: ["date": record.date]
            )
        case let check as PregnancyCheck:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: check),
                preciseDates: [
                    "date": check.date,
                    "dueDate": check.dueDate,
                ]
            )
        case let session as FieldCheckSession:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: session),
                preciseDates: [
                    "startedAt": session.startedAt,
                    "completedAt": session.completedAt,
                    "pastureArchivedAt": session.pastureArchivedAt,
                ]
            )
        case let check as FieldCheckAnimalCheck:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: check),
                preciseDates: [
                    "countedAt": check.countedAt,
                    "missingConfirmedAt": check.missingConfirmedAt,
                ]
            )
        case let finding as FieldCheckFinding:
            return snapshot(
                HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: finding),
                preciseDates: ["recordedAt": finding.recordedAt]
            )
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
        var fields = snapshot(
            HerdSharingSwiftDataImportEngine.conflictFieldSnapshot(for: animal),
            preciseDates: [
                "birthDate": animal.birthDate,
                "saleDate": animal.saleDate,
                "deathDate": animal.deathDate,
                "softDeletedAt": animal.softDeletedAt,
            ]
        )
        fields["sireAnimalPublicID"] = value(animal.sireAnimal?.publicID)
        fields["damAnimalPublicID"] = value(animal.damAnimal?.publicID)
        return fields
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

    /// Conflict review predates revision lineage and formats dates to whole seconds.
    /// Override date fields at this boundary so every revision snapshot preserves
    /// changes that occur within the same second. Device-local fields are removed
    /// because they are intentionally absent from the shared bridge payload.
    private static func snapshot(
        _ fields: CollaborationFieldSnapshot,
        preciseDates: [String: Date?],
        excluding excludedFields: Set<String> = []
    ) -> CollaborationFieldSnapshot {
        var fields = fields
        for (fieldName, date) in preciseDates {
            fields[fieldName] = value(date)
        }
        for fieldName in excludedFields {
            fields.removeValue(forKey: fieldName)
        }
        return fields
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

    private static func value(_ value: Date?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        return self.value(value)
    }

    private static func value(_ value: UUID) -> HerdSharingBridgeConflictValue {
        HerdSharingBridgeConflictValue(type: .uuid, encodedValue: value.uuidString)
    }

    private static func value(_ value: UUID?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        return HerdSharingBridgeConflictValue(type: .uuid, encodedValue: value.uuidString)
    }
}
