import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func makeRepairPlan(
        loaded: LoadedRecords,
        resolutions: [String: String] = [:]
    ) -> RepairPlan {
        let nodes = makeAggregateNodes(loaded: loaded)
        let graphFingerprints = relationshipFingerprints(loaded: loaded, nodes: nodes)
        let relationshipContext = relationshipContexts(loaded: loaded, nodes: nodes)
        let revisionMetadata = preferredRevisionMetadata(loaded.revisionRecords)

        var plans = PublicIDRepairEntityType.allCases.map { entityType in
            makeEntityPlan(
                nodes: nodes.filter { $0.entityType == entityType },
                entityType: entityType,
                graphFingerprintByLocalIdentifier: graphFingerprints,
                relationshipContextByLocalIdentifier: relationshipContext,
                revisionMetadata: revisionMetadata,
                resolutions: resolutions
            )
        }

        let treatmentLocations = makeTreatmentItemLocations(loaded: loaded)
        mergeTreatmentItemPlan(
            makeTreatmentItemPlan(
                locations: treatmentLocations.filter {
                    $0.entityType == .workingProtocolTemplate
                },
                entityType: .workingProtocolTemplate,
                graphFingerprintByLocalIdentifier: graphFingerprints
            ),
            into: &plans,
            entityType: .workingProtocolTemplate
        )
        mergeTreatmentItemPlan(
            makeTreatmentItemPlan(
                locations: treatmentLocations.filter {
                    $0.entityType == .workingSession
                },
                entityType: .workingSession,
                graphFingerprintByLocalIdentifier: graphFingerprints
            ),
            into: &plans,
            entityType: .workingSession
        )

        let allCandidates = plans.flatMap(\.candidates)
        return RepairPlan(
            assessment: PublicIDRepairAssessment(
                scannedAt: .now,
                entities: plans.map(\.assessment)
            ),
            replacements: plans.flatMap(\.replacements),
            candidates: allCandidates,
            unresolvedIssues: plans.flatMap(\.unresolvedIssues),
            graphFingerprintByLocalIdentifier: graphFingerprints,
            treatmentLocations: treatmentLocations,
            bridgeCollisionResolutions: bridgeCollisionResolutions(from: allCandidates)
        )
    }

    func makeAggregateNodes(loaded: LoadedRecords) -> [AggregateNode] {
        var nodes: [AggregateNode] = []
        appendNodes(
            loaded.herds,
            entityType: .herd,
            collaborationType: .herd,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.name.isEmpty ? "Unnamed herd" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.tagColorDefinitions,
            entityType: .tagColorDefinition,
            collaborationType: .tagColorDefinition,
            publicID: { $0.id },
            assign: { $0.id = $1 },
            description: { $0.name.isEmpty ? "Unnamed tag color" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.animalStatusReferences,
            entityType: .animalStatusReference,
            collaborationType: .animalStatusReference,
            publicID: { $0.id },
            assign: { $0.id = $1 },
            description: { $0.name.isEmpty ? "Unnamed status" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.pastureGroups,
            entityType: .pastureGroup,
            collaborationType: .pastureGroup,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.name.isEmpty ? "Unnamed pasture group" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.pastures,
            entityType: .pasture,
            collaborationType: .pasture,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.name.isEmpty ? "Unnamed pasture" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.animals,
            entityType: .animal,
            collaborationType: .animal,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { self.animalDescription($0) },
            to: &nodes
        )
        appendNodes(
            loaded.animalTags,
            entityType: .animalTag,
            collaborationType: .animalTag,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: {
                $0.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \($0.normalizedNumber)"
            },
            to: &nodes
        )
        appendNodes(
            loaded.movements,
            entityType: .movement,
            collaborationType: .movement,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Movement on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            to: &nodes
        )
        appendNodes(
            loaded.statusRecords,
            entityType: .statusRecord,
            collaborationType: .statusRecord,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Status change on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            to: &nodes
        )
        appendNodes(
            loaded.workingProtocolTemplates,
            entityType: .workingProtocolTemplate,
            collaborationType: .workingProtocolTemplate,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.name.isEmpty ? "Unnamed working protocol" : $0.name },
            to: &nodes
        )
        appendNodes(
            loaded.workingSessions,
            entityType: .workingSession,
            collaborationType: .workingSession,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Working session on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            to: &nodes
        )
        appendNodes(
            loaded.workingQueueItems,
            entityType: .workingQueueItem,
            collaborationType: .workingQueueItem,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Working item for \(self.animalDescription($0.animal))" },
            to: &nodes
        )
        appendNodes(
            loaded.workingTreatmentRecords,
            entityType: .workingTreatmentRecord,
            collaborationType: .workingTreatmentRecord,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.itemName.isEmpty ? "Unnamed treatment" : $0.itemName },
            to: &nodes
        )
        appendNodes(
            loaded.healthRecords,
            entityType: .healthRecord,
            collaborationType: .healthRecord,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.treatment.isEmpty ? "Health record" : $0.treatment },
            to: &nodes
        )
        appendNodes(
            loaded.pregnancyChecks,
            entityType: .pregnancyCheck,
            collaborationType: .pregnancyCheck,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Pregnancy check on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            to: &nodes
        )
        appendNodes(
            loaded.fieldCheckSessions,
            entityType: .fieldCheckSession,
            collaborationType: .fieldCheckSession,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: {
                "Field check for \($0.pastureNameSnapshot.isEmpty ? "unknown pasture" : $0.pastureNameSnapshot)"
            },
            to: &nodes
        )
        appendNodes(
            loaded.fieldCheckAnimalChecks,
            entityType: .fieldCheckAnimalCheck,
            collaborationType: .fieldCheckAnimalCheck,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { "Animal check \($0.displayTagNumber)" },
            to: &nodes
        )
        appendNodes(
            loaded.fieldCheckFindings,
            entityType: .fieldCheckFinding,
            collaborationType: .fieldCheckFinding,
            publicID: { $0.publicID },
            assign: { $0.publicID = $1 },
            description: { $0.note.isEmpty ? "Field check finding" : $0.note },
            to: &nodes
        )
        return nodes
    }

    private func bridgeCollisionResolutions(
        from candidates: [DuplicateCandidate]
    ) -> [PublicIDRepairBridgeCollisionResolution] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            "\(candidate.entityType.rawValue)|\(candidate.retainedPublicID.uuidString.lowercased())"
        }
        return grouped.values.compactMap { group in
            let herdIDs = Set(group.compactMap(\.herdPublicID))
            guard herdIDs.count > 1,
                  let owner = group.first(where: {
                      $0.resultingPublicID == $0.retainedPublicID && $0.herdPublicID != nil
                  }),
                  let ownerHerdID = owner.herdPublicID else {
                return nil
            }
            return makePublicIDRepairBridgeCollisionResolution(
                entityType: owner.entityType,
                retainedPublicID: owner.retainedPublicID,
                selectedHerdPublicID: ownerHerdID,
                herdPublicIDs: Array(herdIDs)
            )
        }.sorted { $0.id < $1.id }
    }
}
