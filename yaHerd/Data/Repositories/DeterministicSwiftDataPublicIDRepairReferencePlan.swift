import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func plannedReferenceUpdates(
        loaded: LoadedRecords,
        plan: RepairPlan,
        resolutions: [String: String]
    ) throws -> [PlannedReferenceUpdate] {
        var updates: [PlannedReferenceUpdate] = []

        for animal in loaded.animals {
            try appendLookupReferenceUpdate(
                entityType: .animal,
                model: animal,
                recordDescription: animalDescription(animal),
                fieldName: "tagColorID",
                currentID: { animal.tagColorID },
                sourceHerd: animal.herd,
                records: loaded.tagColorDefinitions,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { animal.tagColorID = $0 },
                to: &updates
            )
            try appendLookupReferenceUpdate(
                entityType: .animal,
                model: animal,
                recordDescription: animalDescription(animal),
                fieldName: "statusReferenceID",
                currentID: { animal.statusReferenceID },
                sourceHerd: animal.herd,
                records: loaded.animalStatusReferences,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { animal.statusReferenceID = $0 },
                to: &updates
            )
        }

        for tag in loaded.animalTags {
            let sourceHerd: Herd?
            if let herd = tag.herd {
                sourceHerd = herd
            } else {
                sourceHerd = tag.animal?.herd
            }
            try appendLookupReferenceUpdate(
                entityType: .animalTag,
                model: tag,
                recordDescription: tag.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \(tag.normalizedNumber)",
                fieldName: "colorID",
                currentID: { tag.colorID },
                sourceHerd: sourceHerd,
                records: loaded.tagColorDefinitions,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { tag.colorID = $0 },
                to: &updates
            )
        }

        for record in loaded.statusRecords {
            let sourceHerd: Herd?
            if let herd = record.herd {
                sourceHerd = herd
            } else {
                sourceHerd = record.animal?.herd
            }
            try appendLookupReferenceUpdate(
                entityType: .statusRecord,
                model: record,
                recordDescription: "Status change on \(record.date.formatted(date: .abbreviated, time: .omitted))",
                fieldName: "oldStatusReferenceID",
                currentID: { record.oldStatusReferenceID },
                sourceHerd: sourceHerd,
                records: loaded.animalStatusReferences,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { record.oldStatusReferenceID = $0 },
                to: &updates
            )
            try appendLookupReferenceUpdate(
                entityType: .statusRecord,
                model: record,
                recordDescription: "Status change on \(record.date.formatted(date: .abbreviated, time: .omitted))",
                fieldName: "newStatusReferenceID",
                currentID: { record.newStatusReferenceID },
                sourceHerd: sourceHerd,
                records: loaded.animalStatusReferences,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { record.newStatusReferenceID = $0 },
                to: &updates
            )
        }

        for session in loaded.fieldCheckSessions {
            let description = "Field check for \(session.pastureNameSnapshot.isEmpty ? "unknown pasture" : session.pastureNameSnapshot)"
            if let pasture = session.pasture {
                let pastureLocalIdentifier = localRecordIdentifier(pasture)
                let desiredID: UUID
                if let candidate = plan.candidateByLocalIdentifier[pastureLocalIdentifier] {
                    desiredID = candidate.resultingPublicID
                } else {
                    desiredID = pasture.publicID
                }
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckSession,
                    model: session,
                    recordDescription: description,
                    fieldName: "pastureID",
                    currentID: { session.pastureID },
                    desiredID: desiredID,
                    assign: { session.pastureID = $0 },
                    plan: plan,
                    to: &updates
                )
            } else {
                let evidenceMatchingLocalIdentifiers = fieldCheckPastureEvidenceIdentifiers(
                    for: session,
                    records: loaded.pastures
                )
                try appendSnapshotReferenceUpdate(
                    entityType: .fieldCheckSession,
                    model: session,
                    recordDescription: description,
                    fieldName: "pastureID",
                    currentID: { session.pastureID },
                    sourceHerd: session.herd,
                    records: loaded.pastures,
                    publicID: { $0.publicID },
                    herd: { $0.herd },
                    targetDescription: "pasture",
                    evidenceMatchingLocalIdentifiers: evidenceMatchingLocalIdentifiers,
                    plan: plan,
                    resolutions: resolutions,
                    assign: { session.pastureID = $0 },
                    to: &updates
                )
            }
        }

        for check in loaded.fieldCheckAnimalChecks {
            let sourceHerd: Herd?
            if let herd = check.herd {
                sourceHerd = herd
            } else if let herd = check.session?.herd {
                sourceHerd = herd
            } else {
                sourceHerd = check.animal?.herd
            }
            if let animal = check.animal {
                let animalLocalIdentifier = localRecordIdentifier(animal)
                let desiredID: UUID
                if let candidate = plan.candidateByLocalIdentifier[animalLocalIdentifier] {
                    desiredID = candidate.resultingPublicID
                } else {
                    desiredID = animal.publicID
                }
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckAnimalCheck,
                    model: check,
                    recordDescription: "Animal check \(check.displayTagNumber)",
                    fieldName: "animalIDSnapshot",
                    currentID: { check.animalIDSnapshot },
                    desiredID: desiredID,
                    assign: { check.animalIDSnapshot = $0 },
                    plan: plan,
                    to: &updates
                )
            } else {
                let evidenceMatchingLocalIdentifiers = fieldCheckAnimalEvidenceIdentifiers(
                    for: check,
                    records: loaded.animals
                )
                try appendSnapshotReferenceUpdate(
                    entityType: .fieldCheckAnimalCheck,
                    model: check,
                    recordDescription: "Animal check \(check.displayTagNumber)",
                    fieldName: "animalIDSnapshot",
                    currentID: { check.animalIDSnapshot },
                    sourceHerd: sourceHerd,
                    records: loaded.animals,
                    publicID: { $0.publicID },
                    herd: { $0.herd },
                    targetDescription: "animal",
                    evidenceMatchingLocalIdentifiers: evidenceMatchingLocalIdentifiers,
                    plan: plan,
                    resolutions: resolutions,
                    assign: { check.animalIDSnapshot = $0 },
                    to: &updates
                )
            }
            try appendLookupReferenceUpdate(
                entityType: .fieldCheckAnimalCheck,
                model: check,
                recordDescription: "Animal check \(check.displayTagNumber)",
                fieldName: "rosterTagColorID",
                currentID: { check.rosterTagColorID },
                sourceHerd: sourceHerd,
                records: loaded.tagColorDefinitions,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { check.rosterTagColorID = $0 },
                to: &updates
            )
            try appendLookupReferenceUpdate(
                entityType: .fieldCheckAnimalCheck,
                model: check,
                recordDescription: "Animal check \(check.displayTagNumber)",
                fieldName: "damRosterTagColorID",
                currentID: { check.damRosterTagColorID },
                sourceHerd: sourceHerd,
                records: loaded.tagColorDefinitions,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { check.damRosterTagColorID = $0 },
                to: &updates
            )
        }

        for finding in loaded.fieldCheckFindings {
            let sourceHerd: Herd?
            if let herd = finding.herd {
                sourceHerd = herd
            } else if let herd = finding.session?.herd {
                sourceHerd = herd
            } else {
                sourceHerd = finding.animal?.herd
            }
            if let animal = finding.animal {
                let animalLocalIdentifier = localRecordIdentifier(animal)
                let desiredID: UUID
                if let candidate = plan.candidateByLocalIdentifier[animalLocalIdentifier] {
                    desiredID = candidate.resultingPublicID
                } else {
                    desiredID = animal.publicID
                }
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "animalIDSnapshot",
                    currentID: { finding.animalIDSnapshot },
                    desiredID: desiredID,
                    assign: { finding.animalIDSnapshot = $0 },
                    plan: plan,
                    to: &updates
                )
            } else {
                let evidenceMatchingLocalIdentifiers = fieldCheckFindingAnimalEvidenceIdentifiers(
                    for: finding,
                    records: loaded.animals
                )
                try appendSnapshotReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "animalIDSnapshot",
                    currentID: { finding.animalIDSnapshot },
                    sourceHerd: sourceHerd,
                    records: loaded.animals,
                    publicID: { $0.publicID },
                    herd: { $0.herd },
                    targetDescription: "animal",
                    evidenceMatchingLocalIdentifiers: evidenceMatchingLocalIdentifiers,
                    plan: plan,
                    resolutions: resolutions,
                    assign: { finding.animalIDSnapshot = $0 },
                    to: &updates
                )
            }
            if let session = finding.session {
                let sessionLocalIdentifier = localRecordIdentifier(session)
                let desiredID: UUID
                if let candidate = plan.candidateByLocalIdentifier[sessionLocalIdentifier] {
                    desiredID = candidate.resultingPublicID
                } else {
                    desiredID = session.publicID
                }
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "sessionIDSnapshot",
                    currentID: { finding.sessionIDSnapshot },
                    desiredID: desiredID,
                    assign: { finding.sessionIDSnapshot = $0 },
                    plan: plan,
                    to: &updates
                )
            } else {
                let evidenceMatchingLocalIdentifiers = fieldCheckFindingSessionEvidenceIdentifiers(
                    for: finding,
                    records: loaded.fieldCheckSessions
                )
                try appendSnapshotReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "sessionIDSnapshot",
                    currentID: { finding.sessionIDSnapshot },
                    sourceHerd: sourceHerd,
                    records: loaded.fieldCheckSessions,
                    publicID: { $0.publicID },
                    herd: { $0.herd },
                    targetDescription: "field check session",
                    evidenceMatchingLocalIdentifiers: evidenceMatchingLocalIdentifiers,
                    plan: plan,
                    resolutions: resolutions,
                    assign: { finding.sessionIDSnapshot = $0 },
                    to: &updates
                )
            }
            try appendLookupReferenceUpdate(
                entityType: .fieldCheckFinding,
                model: finding,
                recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                fieldName: "animalDisplayTagColorIDSnapshot",
                currentID: { finding.animalDisplayTagColorIDSnapshot },
                sourceHerd: sourceHerd,
                records: loaded.tagColorDefinitions,
                publicID: { $0.id },
                herd: { $0.herd },
                plan: plan,
                resolutions: resolutions,
                assign: { finding.animalDisplayTagColorIDSnapshot = $0 },
                to: &updates
            )
        }

        for treatment in loaded.workingTreatmentRecords {
            guard let desiredID = try repairedTreatmentItemID(
                for: treatment,
                plan: plan,
                resolutions: resolutions
            ) else { continue }
            appendOptionalReferenceUpdate(
                entityType: .workingTreatmentRecord,
                model: treatment,
                recordDescription: treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName,
                fieldName: "treatmentItemID",
                currentID: { treatment.treatmentItemID },
                desiredID: desiredID,
                assign: { treatment.treatmentItemID = $0 },
                plan: plan,
                to: &updates
            )
        }

        var ordering: [(key: String, index: Int)] = []
        ordering.reserveCapacity(updates.count)
        for index in updates.indices {
            let report = updates[index].report
            let key = [
                report.entityType.rawValue,
                report.stableRecordIdentifier,
                report.fieldName,
                String(format: "%08d", index),
            ].joined(separator: "|")
            ordering.append((key: key, index: index))
        }
        ordering.sort { $0.key < $1.key }

        var sortedUpdates: [PlannedReferenceUpdate] = []
        sortedUpdates.reserveCapacity(updates.count)
        for item in ordering {
            sortedUpdates.append(updates[item.index])
        }
        return sortedUpdates
    }

}
