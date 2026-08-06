import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func appendLookupReferenceUpdate<Lookup, Source>(
        entityType: PublicIDRepairEntityType,
        model: Source,
        recordDescription: String,
        fieldName: String,
        currentID: @escaping () -> UUID?,
        sourceHerd: Herd?,
        records: [Lookup],
        publicID: (Lookup) -> UUID,
        herd: (Lookup) -> Herd?,
        plan: RepairPlan,
        resolutions: [String: String],
        assign: @escaping (UUID) -> Void,
        to updates: inout [PlannedReferenceUpdate]
    ) throws where Lookup: PersistentModel, Lookup: CollaborativelyMutableAggregate,
                   Source: PersistentModel, Source: CollaborativelyMutableAggregate {
        guard let current = currentID() else { return }
        let pool = scopedLookupCandidates(
            currentID: current,
            sourceHerd: sourceHerd,
            records: records,
            publicID: publicID,
            herd: herd
        )
        let desiredID: UUID
        if pool.count <= 1 {
            guard let selected = pool.first else { return }
            desiredID = plan.candidateByLocalIdentifier[localRecordIdentifier(selected)]?.resultingPublicID
                ?? publicID(selected)
        } else {
            let candidates = pool.compactMap {
                plan.candidateByLocalIdentifier[localRecordIdentifier($0)]
            }
            let issue = PublicIDRepairUnresolvedReference(
                kind: .lookupReference,
                entityType: entityType,
                recordDescription: recordDescription,
                stableRecordIdentifier: stableSourceIdentifier(model, plan: plan),
                fieldName: fieldName,
                referencedPublicID: current,
                reason: "Multiple lookup records share this public ID. Choose the intended record.",
                candidates: candidates.map(makeResolutionCandidate)
            )
            guard let selectedIdentifier = resolutions[issue.id],
                  let selected = candidates.first(where: {
                      $0.stableRecordIdentifier == selectedIdentifier
                  })
            else {
                throw PublicIDRepairError.invalidResolution(issue.id)
            }
            desiredID = selected.resultingPublicID
        }

        appendOptionalReferenceUpdate(
            entityType: entityType,
            model: model,
            recordDescription: recordDescription,
            fieldName: fieldName,
            currentID: currentID,
            desiredID: desiredID,
            assign: assign,
            plan: plan,
            to: &updates
        )
    }

    func appendOptionalReferenceUpdate<Model>(
        entityType: PublicIDRepairEntityType,
        model: Model,
        recordDescription: String,
        fieldName: String,
        currentID: @escaping () -> UUID?,
        desiredID: UUID?,
        assign: @escaping (UUID) -> Void,
        plan: RepairPlan,
        to updates: inout [PlannedReferenceUpdate]
    ) where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        guard let desiredID, currentID() != desiredID else { return }
        updates.append(
            PlannedReferenceUpdate(
                report: PublicIDRepairReferenceUpdate(
                    entityType: entityType,
                    recordDescription: recordDescription,
                    stableRecordIdentifier: stableSourceIdentifier(model, plan: plan),
                    fieldName: fieldName,
                    previousPublicID: currentID(),
                    repairedPublicID: desiredID
                ),
                readPublicID: currentID,
                assignPublicID: assign
            )
        )
    }

    func treatmentCandidateLocations(
        for treatment: WorkingTreatmentRecord,
        plan: RepairPlan
    ) -> [TreatmentItemLocation] {
        guard let session = treatment.session else { return [] }
        let sessionID = localRecordIdentifier(session)
        let sessionLocations = plan.treatmentLocations.filter {
            $0.ownerLocalIdentifier == sessionID && $0.entityType == .workingSession
        }
        let originalMatches = sessionLocations.filter {
            $0.originalID == treatment.treatmentItemID
        }
        if !originalMatches.isEmpty { return originalMatches }
        let normalizedName = normalizedTreatmentName(treatment.itemName)
        return sessionLocations.filter {
            normalizedTreatmentName($0.item.name) == normalizedName
        }
    }

    func uniquelyMatchedTreatmentLocation(
        for treatment: WorkingTreatmentRecord,
        locations: [TreatmentItemLocation]
    ) -> TreatmentItemLocation? {
        guard !locations.isEmpty else { return nil }
        if locations.count == 1 { return locations[0] }

        let normalizedName = normalizedTreatmentName(treatment.itemName)
        let nameMatches = locations.filter {
            normalizedTreatmentName($0.item.name) == normalizedName
        }
        if nameMatches.count == 1 { return nameMatches[0] }
        let evidencePool = nameMatches.isEmpty ? locations : nameMatches

        let hasDoseEvidence = treatment.doseAmount != nil
            || treatment.doseUnit != nil
            || treatment.administrationRoute != nil
        guard hasDoseEvidence else { return nil }
        let doseMatches = evidencePool.filter { location in
            let dose = location.item.suggestedDose
            if let amount = treatment.doseAmount, dose.amount != amount { return false }
            if let unit = treatment.doseUnit, dose.unit != unit { return false }
            if let route = treatment.administrationRoute, dose.route != route { return false }
            return true
        }
        return doseMatches.count == 1 ? doseMatches[0] : nil
    }

    func repairedTreatmentItemID(
        for treatment: WorkingTreatmentRecord,
        plan: RepairPlan,
        resolutions: [String: String]
    ) throws -> UUID? {
        let locations = treatmentCandidateLocations(for: treatment, plan: plan)
        guard !locations.isEmpty else { return nil }
        let selected: TreatmentItemLocation
        if let matched = uniquelyMatchedTreatmentLocation(for: treatment, locations: locations) {
            selected = matched
        } else {
            let candidates = locations.compactMap {
                plan.candidateByLocalIdentifier[$0.localIdentifier]
            }
            let issue = PublicIDRepairUnresolvedReference(
                kind: .treatmentReference,
                entityType: .workingTreatmentRecord,
                recordDescription: treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName,
                stableRecordIdentifier: stableSourceIdentifier(treatment, plan: plan),
                fieldName: "treatmentItemID",
                referencedPublicID: treatment.treatmentItemID,
                reason: "Multiple planned treatments match this record.",
                candidates: candidates.map(makeResolutionCandidate)
            )
            guard let selectedIdentifier = resolutions[issue.id],
                  let selectedCandidate = candidates.first(where: {
                      $0.stableRecordIdentifier == selectedIdentifier
                  }),
                  let selectedLocation = locations.first(where: {
                      $0.localIdentifier == selectedCandidate.localIdentifier
                  })
            else {
                throw PublicIDRepairError.invalidResolution(issue.id)
            }
            selected = selectedLocation
        }
        return plan.candidateByLocalIdentifier[selected.localIdentifier]?.resultingPublicID
            ?? selected.originalID
    }

    func stableSourceIdentifier<Model>(
        _ model: Model,
        plan: RepairPlan
    ) -> String where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        let localID = localRecordIdentifier(model)
        if let candidate = plan.candidateByLocalIdentifier[localID] {
            return candidate.stableRecordIdentifier
        }
        let entityType = publicIDRepairEntityType(for: model)
        let snapshot = stableSnapshotKey(CollaborationFieldSnapshotProvider.snapshot(for: model))
        let graph = plan.graphFingerprintByLocalIdentifier[localID] ?? ""
        return [
            entityType.rawValue,
            model.collaborationKey.publicID.uuidString.lowercased(),
            deterministicDigest(snapshot),
            graph,
        ].joined(separator: "|")
    }

    func publicIDRepairEntityType(
        for aggregate: any CollaborativelyMutableAggregate
    ) -> PublicIDRepairEntityType {
        switch aggregate {
        case is Herd: .herd
        case is TagColorDefinition: .tagColorDefinition
        case is AnimalStatusReference: .animalStatusReference
        case is PastureGroup: .pastureGroup
        case is Pasture: .pasture
        case is Animal: .animal
        case is AnimalTag: .animalTag
        case is MovementRecord: .movement
        case is StatusRecord: .statusRecord
        case is WorkingProtocolTemplate: .workingProtocolTemplate
        case is WorkingSession: .workingSession
        case is WorkingQueueItem: .workingQueueItem
        case is WorkingTreatmentRecord: .workingTreatmentRecord
        case is HealthRecord: .healthRecord
        case is PregnancyCheck: .pregnancyCheck
        case is FieldCheckSession: .fieldCheckSession
        case is FieldCheckAnimalCheck: .fieldCheckAnimalCheck
        case is FieldCheckFinding: .fieldCheckFinding
        default:
            preconditionFailure("Unsupported collaboratively mutable aggregate: \(type(of: aggregate))")
        }
    }
}
