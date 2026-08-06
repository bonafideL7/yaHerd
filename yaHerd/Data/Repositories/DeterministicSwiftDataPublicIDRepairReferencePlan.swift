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
            try appendLookupReferenceUpdate(
                entityType: .animalTag,
                model: tag,
                recordDescription: tag.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \(tag.normalizedNumber)",
                fieldName: "colorID",
                currentID: { tag.colorID },
                sourceHerd: tag.herd ?? tag.animal?.herd,
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
            let sourceHerd = record.herd ?? record.animal?.herd
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
            if let pasture = session.pasture {
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckSession,
                    model: session,
                    recordDescription: "Field check for \(session.pastureNameSnapshot.isEmpty ? "unknown pasture" : session.pastureNameSnapshot)",
                    fieldName: "pastureID",
                    currentID: { session.pastureID },
                    desiredID: plan.candidateByLocalIdentifier[localRecordIdentifier(pasture)]?.resultingPublicID
                        ?? pasture.publicID,
                    assign: { session.pastureID = $0 },
                    plan: plan,
                    to: &updates
                )
            }
        }

        for check in loaded.fieldCheckAnimalChecks {
            let sourceHerd = check.herd ?? check.session?.herd ?? check.animal?.herd
            if let animal = check.animal {
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckAnimalCheck,
                    model: check,
                    recordDescription: "Animal check \(check.displayTagNumber)",
                    fieldName: "animalIDSnapshot",
                    currentID: { check.animalIDSnapshot },
                    desiredID: plan.candidateByLocalIdentifier[localRecordIdentifier(animal)]?.resultingPublicID
                        ?? animal.publicID,
                    assign: { check.animalIDSnapshot = $0 },
                    plan: plan,
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
            let sourceHerd = finding.herd ?? finding.session?.herd ?? finding.animal?.herd
            if let animal = finding.animal {
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "animalIDSnapshot",
                    currentID: { finding.animalIDSnapshot },
                    desiredID: plan.candidateByLocalIdentifier[localRecordIdentifier(animal)]?.resultingPublicID
                        ?? animal.publicID,
                    assign: { finding.animalIDSnapshot = $0 },
                    plan: plan,
                    to: &updates
                )
            }
            if let session = finding.session {
                appendOptionalReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "sessionIDSnapshot",
                    currentID: { finding.sessionIDSnapshot },
                    desiredID: plan.candidateByLocalIdentifier[localRecordIdentifier(session)]?.resultingPublicID
                        ?? session.publicID,
                    assign: { finding.sessionIDSnapshot = $0 },
                    plan: plan,
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

        return updates.sorted {
            if $0.report.entityType != $1.report.entityType {
                return $0.report.entityType.rawValue < $1.report.entityType.rawValue
            }
            if $0.report.stableRecordIdentifier != $1.report.stableRecordIdentifier {
                return $0.report.stableRecordIdentifier < $1.report.stableRecordIdentifier
            }
            return $0.report.fieldName < $1.report.fieldName
        }
    }

}
