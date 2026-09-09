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
            let selectedLocalIdentifier = localRecordIdentifier(selected)
            if let candidate = plan.candidateByLocalIdentifier[selectedLocalIdentifier] {
                desiredID = candidate.resultingPublicID
            } else {
                desiredID = publicID(selected)
            }
        } else {
            var candidates: [DuplicateCandidate] = []
            candidates.reserveCapacity(pool.count)
            for record in pool {
                if let candidate = plan.candidateByLocalIdentifier[localRecordIdentifier(record)] {
                    candidates.append(candidate)
                }
            }
            var resolutionCandidates: [PublicIDRepairResolutionCandidate] = []
            resolutionCandidates.reserveCapacity(candidates.count)
            for candidate in candidates {
                resolutionCandidates.append(makeResolutionCandidate(candidate))
            }
            let issue = PublicIDRepairUnresolvedReference(
                kind: .lookupReference,
                entityType: entityType,
                recordDescription: recordDescription,
                stableRecordIdentifier: stableSourceIdentifier(model, plan: plan),
                fieldName: fieldName,
                referencedPublicID: current,
                reason: "Multiple lookup records share this public ID. Choose the intended record.",
                candidates: resolutionCandidates
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

    func appendSnapshotReferenceUpdate<Target, Source>(
        entityType: PublicIDRepairEntityType,
        model: Source,
        recordDescription: String,
        fieldName: String,
        currentID: @escaping () -> UUID?,
        sourceHerd: Herd?,
        records: [Target],
        publicID: (Target) -> UUID,
        herd: (Target) -> Herd?,
        targetDescription: String,
        evidenceMatchingLocalIdentifiers: Set<String>,
        plan: RepairPlan,
        resolutions: [String: String],
        assign: @escaping (UUID) -> Void,
        to updates: inout [PlannedReferenceUpdate]
    ) throws where Target: PersistentModel, Target: CollaborativelyMutableAggregate,
                   Source: PersistentModel, Source: CollaborativelyMutableAggregate {
        guard let current = currentID() else { return }
        let pool = scopedLookupCandidates(
            currentID: current,
            sourceHerd: sourceHerd,
            records: records,
            publicID: publicID,
            herd: herd
        )
        guard !pool.isEmpty else { return }

        let selected: Target
        if pool.count == 1 {
            selected = pool[0]
        } else {
            var evidencePool: [Target] = []
            for target in pool {
                if evidenceMatchingLocalIdentifiers.contains(localRecordIdentifier(target)) {
                    evidencePool.append(target)
                }
            }
            if evidencePool.count == 1 {
                selected = evidencePool[0]
            } else {
                var candidates: [(Target, DuplicateCandidate)] = []
                candidates.reserveCapacity(pool.count)
                for target in pool {
                    guard let candidate = plan.candidateByLocalIdentifier[localRecordIdentifier(target)] else {
                        continue
                    }
                    candidates.append((target, candidate))
                }
                var resolutionCandidates: [PublicIDRepairResolutionCandidate] = []
                resolutionCandidates.reserveCapacity(candidates.count)
                for candidate in candidates {
                    resolutionCandidates.append(makeResolutionCandidate(candidate.1))
                }
                let issue = PublicIDRepairUnresolvedReference(
                    kind: .lookupReference,
                    entityType: entityType,
                    recordDescription: recordDescription,
                    stableRecordIdentifier: stableSourceIdentifier(model, plan: plan),
                    fieldName: fieldName,
                    referencedPublicID: current,
                    reason: "The live relationship is unavailable and the stored snapshot does not identify exactly one \(targetDescription). Choose the intended record.",
                    candidates: resolutionCandidates
                )
                guard let selectedIdentifier = resolutions[issue.id] else {
                    throw PublicIDRepairError.invalidResolution(issue.id)
                }
                var resolvedTarget: Target?
                for candidate in candidates {
                    if candidate.1.stableRecordIdentifier == selectedIdentifier {
                        resolvedTarget = candidate.0
                        break
                    }
                }
                guard let resolvedTarget else {
                    throw PublicIDRepairError.invalidResolution(issue.id)
                }
                selected = resolvedTarget
            }
        }

        let selectedLocalIdentifier = localRecordIdentifier(selected)
        let desiredID: UUID
        if let candidate = plan.candidateByLocalIdentifier[selectedLocalIdentifier] {
            desiredID = candidate.resultingPublicID
        } else {
            desiredID = publicID(selected)
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
                    repairedPublicID: desiredID,
                    owningHerdPublicID: model.collaborationHerdPublicID
                ),
                readPublicID: currentID,
                assignPublicID: assign
            )
        )
    }

    func fieldCheckPastureSnapshotMatches(
        _ session: FieldCheckSession,
        _ pasture: Pasture
    ) -> Bool {
        let name = normalizedSnapshotText(session.pastureNameSnapshot)
        guard !name.isEmpty else { return false }
        return normalizedSnapshotText(pasture.name) == name
    }

    func fieldCheckAnimalSnapshotMatches(
        _ check: FieldCheckAnimalCheck,
        _ animal: Animal
    ) -> Bool {
        let tag = normalizedSnapshotText(check.rosterTagNumber)
        let name = normalizedSnapshotText(check.animalName)
        let sex = check.animalSex
        let hasEvidence = !tag.isEmpty || !name.isEmpty || sex != .unknown
        guard hasEvidence else { return false }
        if !tag.isEmpty, normalizedSnapshotText(animal.tagNumber) != tag { return false }
        if !name.isEmpty, normalizedSnapshotText(animal.name) != name { return false }
        if sex != .unknown, animal.sex != sex { return false }
        return true
    }

    func fieldCheckFindingAnimalSnapshotMatches(
        _ finding: FieldCheckFinding,
        _ animal: Animal
    ) -> Bool {
        let tag = normalizedSnapshotText(finding.animalDisplayTagNumberSnapshot)
        let name = normalizedSnapshotText(finding.animalNameSnapshot)
        guard !tag.isEmpty || !name.isEmpty else { return false }
        if !tag.isEmpty, normalizedSnapshotText(animal.tagNumber) != tag { return false }
        if !name.isEmpty, normalizedSnapshotText(animal.name) != name { return false }
        return true
    }

    func fieldCheckFindingSessionSnapshotMatches(
        _ finding: FieldCheckFinding,
        _ session: FieldCheckSession
    ) -> Bool {
        let pastureName = normalizedSnapshotText(finding.pastureNameSnapshot)
        guard !pastureName.isEmpty else { return false }
        return normalizedSnapshotText(session.pastureNameSnapshot) == pastureName
    }

    func normalizedSnapshotText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func treatmentCandidateLocations(
        for treatment: WorkingTreatmentRecord,
        plan: RepairPlan
    ) -> [TreatmentItemLocation] {
        guard let session = treatment.session else { return [] }
        let sessionID = localRecordIdentifier(session)
        var sessionLocations: [TreatmentItemLocation] = []
        sessionLocations.reserveCapacity(plan.treatmentLocations.count)
        for location in plan.treatmentLocations {
            if location.ownerLocalIdentifier == sessionID && location.entityType == .workingSession {
                sessionLocations.append(location)
            }
        }

        let treatmentItemID = treatment.treatmentItemID
        var originalMatches: [TreatmentItemLocation] = []
        for location in sessionLocations {
            if location.originalID == treatmentItemID {
                originalMatches.append(location)
            }
        }
        if !originalMatches.isEmpty { return originalMatches }

        let normalizedName = normalizedTreatmentName(treatment.itemName)
        var nameMatches: [TreatmentItemLocation] = []
        for location in sessionLocations {
            if normalizedTreatmentName(location.item.name) == normalizedName {
                nameMatches.append(location)
            }
        }
        return nameMatches
    }

    func uniquelyMatchedTreatmentLocation(
        for treatment: WorkingTreatmentRecord,
        locations: [TreatmentItemLocation]
    ) -> TreatmentItemLocation? {
        guard !locations.isEmpty else { return nil }
        if locations.count == 1 { return locations[0] }

        let normalizedName = normalizedTreatmentName(treatment.itemName)
        var nameMatches: [TreatmentItemLocation] = []
        for location in locations {
            if normalizedTreatmentName(location.item.name) == normalizedName {
                nameMatches.append(location)
            }
        }
        if nameMatches.count == 1 { return nameMatches[0] }
        let evidencePool = nameMatches.isEmpty ? locations : nameMatches

        let doseAmount = treatment.doseAmount
        let doseUnit = treatment.doseUnit
        let administrationRoute = treatment.administrationRoute
        let hasDoseEvidence = doseAmount != nil
            || doseUnit != nil
            || administrationRoute != nil
        guard hasDoseEvidence else { return nil }

        var doseMatches: [TreatmentItemLocation] = []
        for location in evidencePool {
            let dose = location.item.suggestedDose
            if let amount = doseAmount, dose.amount != amount { continue }
            if let unit = doseUnit, dose.unit != unit { continue }
            if let route = administrationRoute, dose.route != route { continue }
            doseMatches.append(location)
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
            var candidates: [DuplicateCandidate] = []
            candidates.reserveCapacity(locations.count)
            for location in locations {
                if let candidate = plan.candidateByLocalIdentifier[location.localIdentifier] {
                    candidates.append(candidate)
                }
            }
            var resolutionCandidates: [PublicIDRepairResolutionCandidate] = []
            resolutionCandidates.reserveCapacity(candidates.count)
            for candidate in candidates {
                resolutionCandidates.append(makeResolutionCandidate(candidate))
            }
            let issue = PublicIDRepairUnresolvedReference(
                kind: .treatmentReference,
                entityType: .workingTreatmentRecord,
                recordDescription: treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName,
                stableRecordIdentifier: stableSourceIdentifier(treatment, plan: plan),
                fieldName: "treatmentItemID",
                referencedPublicID: treatment.treatmentItemID,
                reason: "Multiple planned treatments match this record.",
                candidates: resolutionCandidates
            )
            guard let selectedIdentifier = resolutions[issue.id] else {
                throw PublicIDRepairError.invalidResolution(issue.id)
            }
            var selectedCandidate: DuplicateCandidate?
            for candidate in candidates {
                if candidate.stableRecordIdentifier == selectedIdentifier {
                    selectedCandidate = candidate
                    break
                }
            }
            guard let selectedCandidate else {
                throw PublicIDRepairError.invalidResolution(issue.id)
            }
            var selectedLocation: TreatmentItemLocation?
            for location in locations {
                if location.localIdentifier == selectedCandidate.localIdentifier {
                    selectedLocation = location
                    break
                }
            }
            guard let selectedLocation else {
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
