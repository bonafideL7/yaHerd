import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func validationIssues(
        loaded: LoadedRecords,
        replacements: [PlannedReplacement],
        referenceUpdates: [PlannedReferenceUpdate]
    ) throws -> [String] {
        var issues: [String] = []
        appendDuplicateValidationIssues(loaded.herds, entityType: .herd, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.tagColorDefinitions, entityType: .tagColorDefinition, publicID: { $0.id }, to: &issues)
        appendDuplicateValidationIssues(loaded.animalStatusReferences, entityType: .animalStatusReference, publicID: { $0.id }, to: &issues)
        appendDuplicateValidationIssues(loaded.pastureGroups, entityType: .pastureGroup, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.pastures, entityType: .pasture, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.animals, entityType: .animal, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.animalTags, entityType: .animalTag, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.movements, entityType: .movement, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.statusRecords, entityType: .statusRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingProtocolTemplates, entityType: .workingProtocolTemplate, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingSessions, entityType: .workingSession, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingQueueItems, entityType: .workingQueueItem, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingTreatmentRecords, entityType: .workingTreatmentRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.healthRecords, entityType: .healthRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.pregnancyChecks, entityType: .pregnancyCheck, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckSessions, entityType: .fieldCheckSession, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckAnimalChecks, entityType: .fieldCheckAnimalCheck, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckFindings, entityType: .fieldCheckFinding, publicID: { $0.publicID }, to: &issues)

        for template in loaded.workingProtocolTemplates where Set(template.items.map(\.id)).count != template.items.count {
            issues.append("A working protocol template still contains duplicate treatment item IDs.")
        }
        for session in loaded.workingSessions where Set(session.protocolItems.map(\.id)).count != session.protocolItems.count {
            issues.append("A working session still contains duplicate treatment item IDs.")
        }

        for replacement in replacements where replacement.readPublicID() != replacement.report.replacementPublicID {
            issues.append("\(replacement.report.entityType.displayName) replacement did not retain its assigned public ID.")
        }
        for update in referenceUpdates where update.readPublicID() != update.report.repairedPublicID {
            issues.append("\(update.report.entityType.displayName) \(update.report.fieldName) still points to an obsolete public ID.")
        }
        for treatment in loaded.workingTreatmentRecords {
            guard let session = treatment.session else { continue }
            if !session.protocolItems.contains(where: { $0.id == treatment.treatmentItemID }) {
                issues.append("A working treatment record still points to an obsolete treatment item ID.")
            }
        }

        let revisionRecords = try fetchAll(CollaborationRevisionRecord.self)
        let groupedRevisionRecords = Dictionary(grouping: revisionRecords, by: \.key)
        for aggregate in loaded.allAggregates {
            let key = aggregate.collaborationKey
            let matching = groupedRevisionRecords[key] ?? []
            if matching.count != 1 {
                issues.append("Revision metadata count for \(key.storageKey) is \(matching.count), expected 1.")
                continue
            }
            guard let record = matching.first else { continue }
            if record.herdPublicID != aggregate.collaborationHerdPublicID {
                issues.append("Revision metadata herd scope is stale for \(key.storageKey).")
            }
            if record.metadata.currentFieldValues != CollaborationFieldSnapshotProvider.snapshot(for: aggregate) {
                issues.append("Revision metadata fields are stale for \(key.storageKey).")
            }
        }
        return issues
    }

    func appendDuplicateValidationIssues<Model>(
        _ records: [Model],
        entityType: PublicIDRepairEntityType,
        publicID: (Model) -> UUID,
        to issues: inout [String]
    ) {
        let duplicates = Dictionary(grouping: records, by: publicID).filter { $0.value.count > 1 }
        if !duplicates.isEmpty {
            issues.append("\(entityType.displayName) still contain \(duplicates.count) duplicate public-ID groups.")
        }
    }

    func recordDescription(
        for aggregate: any CollaborativelyMutableAggregate
    ) -> String {
        switch aggregate {
        case let herd as Herd: return herd.name.isEmpty ? "Unnamed herd" : herd.name
        case let definition as TagColorDefinition: return definition.name.isEmpty ? "Unnamed tag color" : definition.name
        case let reference as AnimalStatusReference: return reference.name.isEmpty ? "Unnamed status" : reference.name
        case let group as PastureGroup: return group.name.isEmpty ? "Unnamed pasture group" : group.name
        case let pasture as Pasture: return pasture.name.isEmpty ? "Unnamed pasture" : pasture.name
        case let animal as Animal: return animalDescription(animal)
        case let tag as AnimalTag: return tag.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \(tag.normalizedNumber)"
        case let movement as MovementRecord: return "Movement on \(movement.date.formatted(date: .abbreviated, time: .omitted))"
        case let status as StatusRecord: return "Status change on \(status.date.formatted(date: .abbreviated, time: .omitted))"
        case let template as WorkingProtocolTemplate: return template.name.isEmpty ? "Unnamed working protocol" : template.name
        case let session as WorkingSession: return "Working session on \(session.date.formatted(date: .abbreviated, time: .omitted))"
        case let item as WorkingQueueItem: return "Working item for \(animalDescription(item.animal))"
        case let treatment as WorkingTreatmentRecord: return treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName
        case let health as HealthRecord: return health.treatment.isEmpty ? "Health record" : health.treatment
        case let check as PregnancyCheck: return "Pregnancy check on \(check.date.formatted(date: .abbreviated, time: .omitted))"
        case let session as FieldCheckSession: return "Field check for \(session.pastureNameSnapshot.isEmpty ? "unknown pasture" : session.pastureNameSnapshot)"
        case let check as FieldCheckAnimalCheck: return "Animal check \(check.displayTagNumber)"
        case let finding as FieldCheckFinding: return finding.note.isEmpty ? "Field check finding" : finding.note
        default: return aggregate.collaborationKey.storageKey
        }
    }
}
