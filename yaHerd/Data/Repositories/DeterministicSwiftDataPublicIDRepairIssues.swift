import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func unresolvedReferences(
        loaded: LoadedRecords,
        plan: RepairPlan,
        resolutions: [String: String]
    ) -> [PublicIDRepairUnresolvedReference] {
        var issues: [PublicIDRepairUnresolvedReference] = []

        for animal in loaded.animals {
            appendLookupIssue(
                currentID: animal.tagColorID,
                sourceHerd: animal.herd,
                lookupRecords: loaded.tagColorDefinitions,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .animal,
                sourceModel: animal,
                recordDescription: animalDescription(animal),
                fieldName: "tagColorID",
                lookupDescription: "tag color",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
            appendLookupIssue(
                currentID: animal.statusReferenceID,
                sourceHerd: animal.herd,
                lookupRecords: loaded.animalStatusReferences,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .animal,
                sourceModel: animal,
                recordDescription: animalDescription(animal),
                fieldName: "statusReferenceID",
                lookupDescription: "status reference",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
        }

        for tag in loaded.animalTags {
            appendLookupIssue(
                currentID: tag.colorID,
                sourceHerd: tag.herd ?? tag.animal?.herd,
                lookupRecords: loaded.tagColorDefinitions,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .animalTag,
                sourceModel: tag,
                recordDescription: tag.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \(tag.normalizedNumber)",
                fieldName: "colorID",
                lookupDescription: "tag color",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
        }

        for record in loaded.statusRecords {
            let sourceHerd = record.herd ?? record.animal?.herd
            appendLookupIssue(
                currentID: record.oldStatusReferenceID,
                sourceHerd: sourceHerd,
                lookupRecords: loaded.animalStatusReferences,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .statusRecord,
                sourceModel: record,
                recordDescription: "Status change on \(record.date.formatted(date: .abbreviated, time: .omitted))",
                fieldName: "oldStatusReferenceID",
                lookupDescription: "status reference",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
            appendLookupIssue(
                currentID: record.newStatusReferenceID,
                sourceHerd: sourceHerd,
                lookupRecords: loaded.animalStatusReferences,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .statusRecord,
                sourceModel: record,
                recordDescription: "Status change on \(record.date.formatted(date: .abbreviated, time: .omitted))",
                fieldName: "newStatusReferenceID",
                lookupDescription: "status reference",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
        }

        for check in loaded.fieldCheckAnimalChecks {
            let sourceHerd = check.herd ?? check.session?.herd ?? check.animal?.herd
            appendLookupIssue(
                currentID: check.rosterTagColorID,
                sourceHerd: sourceHerd,
                lookupRecords: loaded.tagColorDefinitions,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .fieldCheckAnimalCheck,
                sourceModel: check,
                recordDescription: "Animal check \(check.displayTagNumber)",
                fieldName: "rosterTagColorID",
                lookupDescription: "tag color",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
            appendLookupIssue(
                currentID: check.damRosterTagColorID,
                sourceHerd: sourceHerd,
                lookupRecords: loaded.tagColorDefinitions,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .fieldCheckAnimalCheck,
                sourceModel: check,
                recordDescription: "Animal check \(check.displayTagNumber)",
                fieldName: "damRosterTagColorID",
                lookupDescription: "tag color",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
        }

        for finding in loaded.fieldCheckFindings {
            appendLookupIssue(
                currentID: finding.animalDisplayTagColorIDSnapshot,
                sourceHerd: finding.herd ?? finding.session?.herd ?? finding.animal?.herd,
                lookupRecords: loaded.tagColorDefinitions,
                lookupPublicID: { $0.id },
                lookupHerd: { $0.herd },
                sourceEntityType: .fieldCheckFinding,
                sourceModel: finding,
                recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                fieldName: "animalDisplayTagColorIDSnapshot",
                lookupDescription: "tag color",
                plan: plan,
                resolutions: resolutions,
                to: &issues
            )
        }

        for treatment in loaded.workingTreatmentRecords {
            if let issue = treatmentIssue(
                treatment,
                plan: plan,
                resolutions: resolutions
            ) {
                issues.append(issue)
            }
        }

        return issues.sorted {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            if $0.stableRecordIdentifier != $1.stableRecordIdentifier {
                return $0.stableRecordIdentifier < $1.stableRecordIdentifier
            }
            return $0.fieldName < $1.fieldName
        }
    }

    func appendLookupIssue<Lookup, Source>(
        currentID: UUID?,
        sourceHerd: Herd?,
        lookupRecords: [Lookup],
        lookupPublicID: (Lookup) -> UUID,
        lookupHerd: (Lookup) -> Herd?,
        sourceEntityType: PublicIDRepairEntityType,
        sourceModel: Source,
        recordDescription: String,
        fieldName: String,
        lookupDescription: String,
        plan: RepairPlan,
        resolutions: [String: String],
        to issues: inout [PublicIDRepairUnresolvedReference]
    ) where Lookup: PersistentModel, Lookup: CollaborativelyMutableAggregate,
            Source: PersistentModel, Source: CollaborativelyMutableAggregate {
        guard let currentID else { return }
        let pool = scopedLookupCandidates(
            currentID: currentID,
            sourceHerd: sourceHerd,
            records: lookupRecords,
            publicID: lookupPublicID,
            herd: lookupHerd
        )
        guard pool.count > 1 else { return }

        let candidates = pool.compactMap {
            plan.candidateByLocalIdentifier[localRecordIdentifier($0)]
        }.map(makeResolutionCandidate)
        let sourceIdentifier = stableSourceIdentifier(sourceModel, plan: plan)
        let issue = PublicIDRepairUnresolvedReference(
            kind: .lookupReference,
            entityType: sourceEntityType,
            recordDescription: recordDescription,
            stableRecordIdentifier: sourceIdentifier,
            fieldName: fieldName,
            referencedPublicID: currentID,
            reason: "Multiple \(lookupDescription) records share this ID in the source herd. Choose the intended record before repair.",
            candidates: candidates
        )
        guard let selected = resolutions[issue.id],
              candidates.contains(where: { $0.stableRecordIdentifier == selected })
        else {
            issues.append(issue)
            return
        }
    }

    func treatmentIssue(
        _ treatment: WorkingTreatmentRecord,
        plan: RepairPlan,
        resolutions: [String: String]
    ) -> PublicIDRepairUnresolvedReference? {
        let locations = treatmentCandidateLocations(for: treatment, plan: plan)
        guard locations.count > 1 else { return nil }
        if uniquelyMatchedTreatmentLocation(for: treatment, locations: locations) != nil {
            return nil
        }

        let candidates = locations.compactMap {
            plan.candidateByLocalIdentifier[$0.localIdentifier]
        }.map(makeResolutionCandidate)
        let issue = PublicIDRepairUnresolvedReference(
            kind: .treatmentReference,
            entityType: .workingTreatmentRecord,
            recordDescription: treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName,
            stableRecordIdentifier: stableSourceIdentifier(treatment, plan: plan),
            fieldName: "treatmentItemID",
            referencedPublicID: treatment.treatmentItemID,
            reason: "More than one planned treatment has the same identifier and the stored name, amount, unit, and route do not identify exactly one item. Choose the intended treatment.",
            candidates: candidates
        )
        guard let selected = resolutions[issue.id],
              candidates.contains(where: { $0.stableRecordIdentifier == selected })
        else { return issue }
        return nil
    }

    func makeResolutionCandidate(
        _ candidate: DuplicateCandidate
    ) -> PublicIDRepairResolutionCandidate {
        PublicIDRepairResolutionCandidate(
            stableRecordIdentifier: candidate.stableRecordIdentifier,
            recordDescription: candidate.recordDescription,
            detail: candidate.detail,
            resultingPublicID: candidate.resultingPublicID
        )
    }

    func scopedLookupCandidates<Model>(
        currentID: UUID,
        sourceHerd: Herd?,
        records: [Model],
        publicID: (Model) -> UUID,
        herd: (Model) -> Herd?
    ) -> [Model] where Model: PersistentModel {
        let candidates = records.filter { publicID($0) == currentID }
        guard candidates.count > 1 else { return candidates }
        let sourceScope = sourceHerd.map(ObjectIdentifier.init)
        let scoped = candidates.filter { herd($0).map(ObjectIdentifier.init) == sourceScope }
        return scoped.isEmpty ? candidates : scoped
    }

}
